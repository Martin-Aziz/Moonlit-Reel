//! db.rs — Embedded sled key-value database
//!
//! Stores library metadata cache, audiobook resume positions, playback history,
//! smart playlist definitions, and application state. All keys are namespaced
//! by tree name to prevent collisions.

use std::path::Path;

use anyhow::{Context, Result};
use serde::{de::DeserializeOwned, Serialize};
use sled::Db;
use tracing::{debug, info};

use crate::metadata::TrackMetadata;
use crate::audiobook::{Audiobook, Bookmark};

/// Named sled trees within the database
const TREE_TRACKS:         &str = "tracks_v1";
const TREE_AUDIOBOOKS:     &str = "audiobooks_v1";
const TREE_RESUME:         &str = "resume_v1";
const TREE_HISTORY:        &str = "history_v1";
const TREE_BOOKMARKS:      &str = "bookmarks_v1";
const TREE_LIBRARY_ROOTS:  &str = "library_roots_v1";
const TREE_SCHEMA_VERSION: &str = "schema";

const CURRENT_SCHEMA_VERSION: u32 = 1;

/// A resume position entry for any media item.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ResumeEntry {
    pub item_id:      String,
    pub position_secs: f64,
    /// Unix epoch ms of last update
    pub updated_at:   u64,
}

/// A single playback history entry.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct HistoryEntry {
    pub item_id:   String,
    pub played_at: u64,  // Unix epoch ms
}

/// The central persistence layer.
pub struct Database {
    db: Db,
}

impl Database {
    /// Open or create the database at `data_dir`.
    pub fn open(data_dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(data_dir)
            .with_context(|| format!("Cannot create data dir {:?}", data_dir))?;

        let db_path = data_dir.join("library.sled");
        let db = sled::open(&db_path)
            .with_context(|| format!("Cannot open sled database at {:?}", db_path))?;

        let instance = Self { db };
        instance.check_and_migrate_schema()?;

        info!("Sled database opened at {:?}", db_path);
        Ok(instance)
    }

    // ── Tracks ──────────────────────────────────────────────────────────────

    /// Store or update a track's metadata.
    pub fn upsert_track(&self, track: &TrackMetadata) -> Result<()> {
        self.insert(TREE_TRACKS, &track.id, track)
    }

    /// Retrieve a track by its stable ID.
    pub fn get_track(&self, id: &str) -> Result<Option<TrackMetadata>> {
        self.get(TREE_TRACKS, id)
    }

    /// Retrieve all cached tracks.
    pub fn all_tracks(&self) -> Result<Vec<TrackMetadata>> {
        self.get_all(TREE_TRACKS)
    }

    /// Remove a track by ID (e.g. file was deleted).
    pub fn remove_track(&self, id: &str) -> Result<()> {
        let tree = self.db.open_tree(TREE_TRACKS)?;
        tree.remove(id)?;
        Ok(())
    }

    // ── Audiobooks ───────────────────────────────────────────────────────────

    pub fn upsert_audiobook(&self, book: &Audiobook) -> Result<()> {
        self.insert(TREE_AUDIOBOOKS, &book.id, book)
    }

    pub fn get_audiobook(&self, id: &str) -> Result<Option<Audiobook>> {
        self.get(TREE_AUDIOBOOKS, id)
    }

    pub fn all_audiobooks(&self) -> Result<Vec<Audiobook>> {
        self.get_all(TREE_AUDIOBOOKS)
    }

    // ── Resume positions ─────────────────────────────────────────────────────

    /// Persist a resume position for any media item.
    pub fn set_resume(&self, item_id: &str, position_secs: f64) -> Result<()> {
        let entry = ResumeEntry {
            item_id: item_id.to_owned(),
            position_secs,
            updated_at: now_millis(),
        };
        self.insert(TREE_RESUME, item_id, &entry)
    }

    pub fn get_resume(&self, item_id: &str) -> Result<Option<ResumeEntry>> {
        self.get(TREE_RESUME, item_id)
    }

    pub fn clear_resume(&self, item_id: &str) -> Result<()> {
        let tree = self.db.open_tree(TREE_RESUME)?;
        tree.remove(item_id)?;
        Ok(())
    }

    // ── Playback history ─────────────────────────────────────────────────────

    /// Record that an item was played right now.
    pub fn record_play(&self, item_id: &str) -> Result<()> {
        let key = format!("{:020}:{}", now_millis(), item_id);
        let entry = HistoryEntry {
            item_id: item_id.to_owned(),
            played_at: now_millis(),
        };
        self.insert(TREE_HISTORY, &key, &entry)
    }

    /// Retrieve recent play history (most recent first, up to `limit` entries).
    pub fn recent_history(&self, limit: usize) -> Result<Vec<HistoryEntry>> {
        let tree = self.db.open_tree(TREE_HISTORY)?;
        let mut entries: Vec<HistoryEntry> = tree
            .iter()
            .rev()
            .take(limit)
            .filter_map(|r| r.ok())
            .filter_map(|(_, v)| serde_json::from_slice(&v).ok())
            .collect();
        Ok(entries)
    }

    // ── Bookmarks ────────────────────────────────────────────────────────────

    pub fn add_bookmark(&self, bookmark: &Bookmark) -> Result<()> {
        self.insert(TREE_BOOKMARKS, &bookmark.id, bookmark)
    }

    pub fn bookmarks_for_audiobook(&self, audiobook_id: &str) -> Result<Vec<Bookmark>> {
        let tree = self.db.open_tree(TREE_BOOKMARKS)?;
        let all: Vec<Bookmark> = tree
            .iter()
            .filter_map(|r| r.ok())
            .filter_map(|(_, v)| serde_json::from_slice(&v).ok())
            .filter(|b: &Bookmark| b.audiobook_id == audiobook_id)
            .collect();
        Ok(all)
    }

    pub fn remove_bookmark(&self, id: &str) -> Result<()> {
        let tree = self.db.open_tree(TREE_BOOKMARKS)?;
        tree.remove(id)?;
        Ok(())
    }

    // ── Library roots ────────────────────────────────────────────────────────

    /// Persist a Security-Scoped Bookmark blob for a library root.
    pub fn set_library_root_bookmark(&self, path_str: &str, bookmark_data: &[u8]) -> Result<()> {
        let tree = self.db.open_tree(TREE_LIBRARY_ROOTS)?;
        tree.insert(path_str.as_bytes(), bookmark_data)?;
        Ok(())
    }

    pub fn all_library_root_bookmarks(&self) -> Result<Vec<(String, Vec<u8>)>> {
        let tree = self.db.open_tree(TREE_LIBRARY_ROOTS)?;
        let all = tree
            .iter()
            .filter_map(|r| r.ok())
            .filter_map(|(k, v)| {
                let path = String::from_utf8(k.to_vec()).ok()?;
                Some((path, v.to_vec()))
            })
            .collect();
        Ok(all)
    }

    // ── Generic helpers ──────────────────────────────────────────────────────

    fn insert<T: Serialize>(&self, tree_name: &str, key: &str, value: &T) -> Result<()> {
        let tree = self.db.open_tree(tree_name)?;
        let bytes = serde_json::to_vec(value)
            .with_context(|| format!("Serialize failed for key {}", key))?;
        tree.insert(key.as_bytes(), bytes)?;
        debug!("DB insert tree={} key={}", tree_name, key);
        Ok(())
    }

    fn get<T: DeserializeOwned>(&self, tree_name: &str, key: &str) -> Result<Option<T>> {
        let tree = self.db.open_tree(tree_name)?;
        match tree.get(key.as_bytes())? {
            None => Ok(None),
            Some(bytes) => {
                let v = serde_json::from_slice(&bytes)
                    .with_context(|| format!("Deserialize failed for key {}", key))?;
                Ok(Some(v))
            }
        }
    }

    fn get_all<T: DeserializeOwned>(&self, tree_name: &str) -> Result<Vec<T>> {
        let tree = self.db.open_tree(tree_name)?;
        let results = tree
            .iter()
            .filter_map(|r| r.ok())
            .filter_map(|(_, v)| serde_json::from_slice(&v).ok())
            .collect();
        Ok(results)
    }

    fn check_and_migrate_schema(&self) -> Result<()> {
        let tree = self.db.open_tree(TREE_SCHEMA_VERSION)?;
        let key = b"version";
        match tree.get(key)? {
            None => {
                // First run — write current version
                tree.insert(key, CURRENT_SCHEMA_VERSION.to_le_bytes().to_vec())?;
                info!("Initialized schema version {}", CURRENT_SCHEMA_VERSION);
            }
            Some(bytes) => {
                let stored = u32::from_le_bytes(bytes[..4].try_into().unwrap_or([0; 4]));
                if stored < CURRENT_SCHEMA_VERSION {
                    // Future: run migrations here, wipe and rebuild search index, etc.
                    info!("Schema migrated from {} to {}", stored, CURRENT_SCHEMA_VERSION);
                    tree.insert(key, CURRENT_SCHEMA_VERSION.to_le_bytes().to_vec())?;
                }
            }
        }
        Ok(())
    }
}

fn now_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use tempfile::tempdir;
    use crate::metadata::MediaType;

    fn dummy_track(id: &str) -> TrackMetadata {
        TrackMetadata {
            id: id.to_owned(),
            path: PathBuf::from(format!("/music/{}.mp3", id)),
            media_type: MediaType::Audio,
            title: Some("Test Track".to_owned()),
            artist: Some("Test Artist".to_owned()),
            album_artist: None,
            album: Some("Test Album".to_owned()),
            genre: None,
            year: Some(2024),
            track_number: None,
            disc_number: None,
            composer: None,
            comment: None,
            bpm: None,
            duration_secs: 240.0,
            sample_rate: Some(44100),
            bit_rate: None,
            channels: Some(2),
            codec: None,
            artwork_data: None,
            artwork_mime: None,
            file_size_bytes: 8_000_000,
            mtime: 0,
        }
    }

    #[test]
    fn test_upsert_and_retrieve_track() {
        let dir = tempdir().unwrap();
        let db = Database::open(dir.path()).unwrap();

        let track = dummy_track("test-id-1");
        db.upsert_track(&track).unwrap();

        let retrieved = db.get_track("test-id-1").unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().title.as_deref(), Some("Test Track"));
    }

    #[test]
    fn test_resume_position_roundtrip() {
        let dir = tempdir().unwrap();
        let db = Database::open(dir.path()).unwrap();

        db.set_resume("item-42", 123.456).unwrap();
        let entry = db.get_resume("item-42").unwrap().unwrap();
        assert!((entry.position_secs - 123.456).abs() < 0.001);
    }

    #[test]
    fn test_history_ordering() {
        let dir = tempdir().unwrap();
        let db = Database::open(dir.path()).unwrap();

        db.record_play("a").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        db.record_play("b").unwrap();

        let history = db.recent_history(10).unwrap();
        assert_eq!(history[0].item_id, "b", "most recent should be first");
    }

    #[test]
    fn test_remove_track() {
        let dir = tempdir().unwrap();
        let db = Database::open(dir.path()).unwrap();

        db.upsert_track(&dummy_track("del-me")).unwrap();
        db.remove_track("del-me").unwrap();
        assert!(db.get_track("del-me").unwrap().is_none());
    }
}
