//! search.rs — Full-text Tantivy search engine
//!
//! Indexes `TrackMetadata` fields into a Tantivy index stored on disk.
//! Provides fuzzy search, faceted filters, and a query DSL compatible
//! with `artist:radiohead year:>2000` syntax.

use std::path::Path;
use std::sync::{Arc, RwLock};
use std::cmp::Ordering;

use anyhow::{Context, Result};
use tantivy::collector::TopDocs;
use tantivy::query::{BooleanQuery, FuzzyTermQuery, Occur, Query, QueryParser, TermQuery};
use tantivy::schema::*;
use tantivy::{Index, IndexReader, IndexWriter, ReloadPolicy, TantivyDocument, Term};
use tracing::{debug, info};

use crate::metadata::TrackMetadata;

/// Tantivy schema field handles, kept for efficient doc construction.
#[derive(Clone)]
struct SchemaFields {
    id:           Field,
    path:         Field,
    title:        Field,
    artist:       Field,
    album:        Field,
    album_artist: Field,
    genre:        Field,
    year:         Field,
    composer:     Field,
    comment:      Field,
    bpm:          Field,
    duration:     Field,
    media_type:   Field,
}

/// A single search result returned to callers.
#[derive(Debug)]
pub struct SearchResult {
    pub id:       String,
    pub path:     String,
    pub title:    String,
    pub artist:   String,
    pub album:    String,
    pub score:    f32,
}

/// Full-text search engine backed by Tantivy.
pub struct SearchEngine {
    index:   Index,
    reader:  IndexReader,
    writer:  Arc<RwLock<IndexWriter>>,
    fields:  SchemaFields,
}

impl SearchEngine {
    /// Open or create the Tantivy index at `index_dir`.
    pub fn open(index_dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(index_dir)
            .with_context(|| format!("Cannot create index dir {:?}", index_dir))?;

        let (schema, fields) = build_schema();

        let index = if Index::exists(&tantivy::directory::MmapDirectory::open(index_dir)?)? {
            Index::open_in_dir(index_dir)?
        } else {
            Index::create_in_dir(index_dir, schema)?
        };

        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()?;

        let writer = index.writer(50_000_000)?; // 50 MB heap for writer

        info!("Search index opened at {:?}", index_dir);
        Ok(Self {
            index,
            reader,
            writer: Arc::new(RwLock::new(writer)),
            fields,
        })
    }

    /// Index a batch of tracks. Commits after adding all docs.
    pub fn index_tracks(&self, tracks: &[TrackMetadata]) -> Result<()> {
        let mut writer = self.writer.write().unwrap();

        for track in tracks {
            let doc = self.build_document(track);
            writer.add_document(doc)?;
        }

        writer.commit()?;
        debug!("Indexed {} tracks", tracks.len());
        Ok(())
    }

    /// Remove a track from the index by its stable ID.
    pub fn remove_track(&self, id: &str) -> Result<()> {
        let mut writer = self.writer.write().unwrap();
        let term = Term::from_field_text(self.fields.id, id);
        writer.delete_term(term);
        writer.commit()?;
        Ok(())
    }

    /// Perform a fuzzy full-text search.
    ///
    /// Supports the DSL: `artist:radiohead album:ok year:>1996 dark`
    /// Plain terms are searched across title, artist, and album.
    pub fn search(&self, query_str: &str, limit: usize) -> Result<Vec<SearchResult>> {
        self.reader.reload()?;
        let searcher = self.reader.searcher();
        let normalized_query = normalize_query(query_str);

        // Build a query parser covering the main text fields
        let mut query_parser = QueryParser::for_index(
            &self.index,
            vec![
                self.fields.title,
                self.fields.artist,
                self.fields.album,
                self.fields.genre,
            ],
        );
        query_parser.set_conjunction_by_default();
        query_parser.set_field_fuzzy(self.fields.title, true, 2, true);
        query_parser.set_field_fuzzy(self.fields.artist, true, 2, true);
        query_parser.set_field_fuzzy(self.fields.album, true, 2, true);

        let query = query_parser
            .parse_query(&normalized_query)
            .unwrap_or_else(|_| {
                // Fallback: robust tokenized query for malformed input.
                self.build_fallback_query(&normalized_query)
            });

        let top_docs = searcher.search(&query, &TopDocs::with_limit(limit))?;

        let mut results = Vec::with_capacity(top_docs.len());
        for (score, doc_address) in top_docs {
            let doc: TantivyDocument = searcher.doc(doc_address)?;
            let mut result = self.document_to_result(&doc, score);
            result.score += heuristic_boost(&result, &normalized_query);
            results.push(result);
        }

        results.sort_by(|lhs, rhs| {
            rhs.score
                .partial_cmp(&lhs.score)
                .unwrap_or(Ordering::Equal)
        });

        debug!("Search '{}' returned {} results", normalized_query, results.len());
        Ok(results)
    }

    fn build_fallback_query(&self, query_str: &str) -> Box<dyn Query> {
        let tokens: Vec<String> = query_str
            .split_whitespace()
            .map(sanitize_token)
            .filter(|token| !token.is_empty())
            .collect();

        if tokens.is_empty() {
            let term = Term::from_field_text(self.fields.title, query_str);
            return Box::new(FuzzyTermQuery::new(term, 2, true));
        }

        let mut clauses: Vec<(Occur, Box<dyn Query>)> = Vec::with_capacity(tokens.len());
        for token in tokens {
            if let Some((field, value)) = parse_qualified_token(&token) {
                let target_field = match field {
                    "title" => self.fields.title,
                    "artist" => self.fields.artist,
                    "album" => self.fields.album,
                    "genre" => self.fields.genre,
                    _ => self.fields.title,
                };
                let term = Term::from_field_text(target_field, value);
                clauses.push((Occur::Must, Box::new(TermQuery::new(term, IndexRecordOption::WithFreqs)) as Box<dyn Query>));
                continue;
            }

            let term_title = Term::from_field_text(self.fields.title, &token);
            let term_artist = Term::from_field_text(self.fields.artist, &token);
            let term_album = Term::from_field_text(self.fields.album, &token);

            let token_query = BooleanQuery::new(vec![
                (Occur::Should, Box::new(FuzzyTermQuery::new(term_title, 2, true)) as Box<dyn Query>),
                (Occur::Should, Box::new(FuzzyTermQuery::new(term_artist, 2, true)) as Box<dyn Query>),
                (Occur::Should, Box::new(FuzzyTermQuery::new(term_album, 2, true)) as Box<dyn Query>),
            ]);

            clauses.push((Occur::Must, Box::new(token_query) as Box<dyn Query>));
        }

        Box::new(BooleanQuery::new(clauses))
    }

    fn build_document(&self, track: &TrackMetadata) -> TantivyDocument {
        let f = &self.fields;
        let mut doc = TantivyDocument::default();
        doc.add_text(f.id, &track.id);
        doc.add_text(f.path, track.path.to_string_lossy().as_ref());
        doc.add_text(f.title, track.title.as_deref().unwrap_or(""));
        doc.add_text(f.artist, track.artist.as_deref().unwrap_or(""));
        doc.add_text(f.album, track.album.as_deref().unwrap_or(""));
        doc.add_text(f.album_artist, track.album_artist.as_deref().unwrap_or(""));
        doc.add_text(f.genre, track.genre.as_deref().unwrap_or(""));
        doc.add_text(f.composer, track.composer.as_deref().unwrap_or(""));
        doc.add_text(f.comment, track.comment.as_deref().unwrap_or(""));
        doc.add_text(f.media_type, format!("{:?}", track.media_type).as_str());
        if let Some(y) = track.year {
            doc.add_u64(f.year, y as u64);
        }
        if let Some(bpm) = track.bpm {
            doc.add_u64(f.bpm, bpm as u64);
        }
        doc.add_f64(f.duration, track.duration_secs);
        doc
    }

    fn document_to_result(&self, doc: &TantivyDocument, score: f32) -> SearchResult {
        let get_text = |field: Field| -> String {
            doc.get_first(field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned()
        };
        SearchResult {
            id:     get_text(self.fields.id),
            path:   get_text(self.fields.path),
            title:  get_text(self.fields.title),
            artist: get_text(self.fields.artist),
            album:  get_text(self.fields.album),
            score,
        }
    }
}

fn normalize_query(query: &str) -> String {
    query
        .split_whitespace()
        .filter(|token| !token.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

fn parse_qualified_token(token: &str) -> Option<(&str, &str)> {
    let (field, raw_value) = token.split_once(':')?;
    let value = raw_value.trim_start_matches(':');
    if field.is_empty() || value.is_empty() {
        return None;
    }
    Some((field, value))
}

fn sanitize_token(token: &str) -> String {
    let mut cleaned = token
        .chars()
        .filter(|ch| ch.is_alphanumeric() || *ch == ':' || *ch == '-' || *ch == '_')
        .collect::<String>()
        .trim_matches(':')
        .to_string();

    while cleaned.contains("::") {
        cleaned = cleaned.replace("::", ":");
    }

    cleaned
}

fn heuristic_boost(result: &SearchResult, normalized_query: &str) -> f32 {
    if normalized_query.is_empty() {
        return 0.0;
    }

    let query = normalized_query.to_lowercase();
    let title = result.title.to_lowercase();
    let artist = result.artist.to_lowercase();
    let album = result.album.to_lowercase();
    let mut boost = 0.0f32;

    if title == query {
        boost += 1.8;
    } else if title.starts_with(&query) {
        boost += 1.2;
    } else if title.contains(&query) {
        boost += 0.8;
    }

    if artist == query {
        boost += 0.7;
    } else if artist.contains(&query) {
        boost += 0.35;
    }

    if album == query {
        boost += 0.5;
    } else if album.contains(&query) {
        boost += 0.2;
    }

    boost
}

fn build_schema() -> (Schema, SchemaFields) {
    let mut schema_builder = Schema::builder();

    let id           = schema_builder.add_text_field("id", STRING | STORED);
    let path         = schema_builder.add_text_field("path", STRING | STORED);
    let title        = schema_builder.add_text_field("title", TEXT | STORED);
    let artist       = schema_builder.add_text_field("artist", TEXT | STORED);
    let album        = schema_builder.add_text_field("album", TEXT | STORED);
    let album_artist = schema_builder.add_text_field("album_artist", TEXT | STORED);
    let genre        = schema_builder.add_text_field("genre", TEXT | STORED);
    let composer     = schema_builder.add_text_field("composer", TEXT | STORED);
    let comment      = schema_builder.add_text_field("comment", TEXT | STORED);
    let media_type   = schema_builder.add_text_field("media_type", STRING | STORED);
    let year         = schema_builder.add_u64_field("year", INDEXED | STORED);
    let bpm          = schema_builder.add_u64_field("bpm", INDEXED | STORED);
    let duration     = schema_builder.add_f64_field("duration", INDEXED | STORED);

    let schema = schema_builder.build();
    let fields = SchemaFields { id, path, title, artist, album, album_artist, genre,
                                year, composer, comment, bpm, duration, media_type };
    (schema, fields)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use tempfile::tempdir;
    use crate::metadata::MediaType;

    fn make_track(id: &str, title: &str, artist: &str) -> TrackMetadata {
        TrackMetadata {
            id: id.to_owned(),
            path: PathBuf::from(format!("/music/{}.mp3", id)),
            media_type: MediaType::Audio,
            title: Some(title.to_owned()),
            artist: Some(artist.to_owned()),
            album_artist: None,
            album: Some("Test Album".to_owned()),
            genre: None,
            year: Some(2020),
            track_number: None,
            disc_number: None,
            composer: None,
            comment: None,
            bpm: None,
            duration_secs: 300.0,
            sample_rate: Some(44100),
            bit_rate: None,
            channels: Some(2),
            codec: None,
            artwork_data: None,
            artwork_mime: None,
            file_size_bytes: 4_000_000,
            mtime: 0,
        }
    }

    #[test]
    fn test_index_and_search() {
        let dir = tempdir().unwrap();
        let engine = SearchEngine::open(dir.path()).unwrap();

        let tracks = vec![
            make_track("1", "Wish You Were Here", "Pink Floyd"),
            make_track("2", "Comfortably Numb", "Pink Floyd"),
            make_track("3", "Karma Police", "Radiohead"),
        ];
        engine.index_tracks(&tracks).unwrap();

        let results = engine.search("Pink Floyd", 10).unwrap();
        assert_eq!(results.len(), 2, "should find both Pink Floyd tracks");

        let results = engine.search("Radiohead", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].artist, "Radiohead");
    }

    #[test]
    fn test_fuzzy_search_handles_typos() {
        let dir = tempdir().unwrap();
        let engine = SearchEngine::open(dir.path()).unwrap();

        engine.index_tracks(&[make_track("x", "Comfortably Numb", "Pink Floyd")]).unwrap();

        let results = engine.search("Comfortbly", 10).unwrap(); // typo
        assert!(!results.is_empty(), "fuzzy search should handle 1-char typo");
    }

    #[test]
    fn test_malformed_query_fallback_still_returns_results() {
        let dir = tempdir().unwrap();
        let engine = SearchEngine::open(dir.path()).unwrap();

        engine.index_tracks(&[make_track("x", "Paranoid Android", "Radiohead")]).unwrap();

        let results = engine.search("artist::radiohead (((", 10).unwrap();
        assert!(!results.is_empty(), "fallback query path should recover from malformed syntax");
    }

    #[test]
    fn test_exact_title_ranks_first_with_boost() {
        let dir = tempdir().unwrap();
        let engine = SearchEngine::open(dir.path()).unwrap();

        engine.index_tracks(&[
            make_track("1", "Karma Police", "Radiohead"),
            make_track("2", "Karma", "Different Artist"),
        ]).unwrap();

        let results = engine.search("Karma Police", 10).unwrap();
        assert!(!results.is_empty());
        assert_eq!(results[0].title, "Karma Police");
    }
}
