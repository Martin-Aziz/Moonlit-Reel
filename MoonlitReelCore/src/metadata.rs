//! metadata.rs — Media file metadata parsing
//!
//! Uses `id3` for MP3 tags, `metaflac` for FLAC, and `symphonia`
//! as a universal fallback. Emits typed `TrackMetadata` structs
//! with zero-allocation paths where possible.

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use id3::TagLike;
use serde::{Deserialize, Serialize};
use tracing::debug;

/// Unified media item type understood by the library domain.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum MediaType {
    Audio,
    Video,
    Audiobook,
}

/// All metadata associated with a single media file.
///
/// This is the core domain entity shared between the Rust engine and
/// Swift presentation layer via the FFI boundary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackMetadata {
    /// Stable ID: BLAKE3 hash of the canonical filesystem path.
    pub id: String,
    pub path: PathBuf,
    pub media_type: MediaType,

    // ── Tags ───────────────────────────────────────────────────────────────
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album_artist: Option<String>,
    pub album: Option<String>,
    pub genre: Option<String>,
    pub year: Option<u32>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub composer: Option<String>,
    pub comment: Option<String>,
    pub bpm: Option<u32>,

    // ── Technical properties ────────────────────────────────────────────────
    pub duration_secs: f64,
    pub sample_rate: Option<u32>,
    pub bit_rate: Option<u32>,
    pub channels: Option<u8>,
    pub codec: Option<String>,

    // ── Artwork ─────────────────────────────────────────────────────────────
    /// Raw JPEG/PNG bytes of embedded artwork, if present.
    #[serde(skip)]
    pub artwork_data: Option<Vec<u8>>,
    pub artwork_mime: Option<String>,

    // ── Filesystem ──────────────────────────────────────────────────────────
    pub file_size_bytes: u64,
    pub mtime: u64,  // Unix epoch seconds
}

impl TrackMetadata {
    /// Generate a stable ID from the file path.
    pub fn id_from_path(path: &Path) -> String {
        let hash = blake3::hash(path.to_string_lossy().as_bytes());
        hex::encode(hash.as_bytes())
    }

    /// Display name: title or filename stem.
    pub fn display_title(&self) -> &str {
        self.title.as_deref().unwrap_or_else(|| {
            self.path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Unknown")
        })
    }
}

/// Stateless parser; preferred as an `Arc<MetadataParser>` shared across threads.
pub struct MetadataParser;

impl MetadataParser {
    pub fn new() -> Self {
        Self
    }

    /// Parse metadata from any supported media file.
    ///
    /// Priority: native crate parser → symphonia fallback.
    pub fn parse(&self, path: &Path) -> Result<TrackMetadata> {
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase())
            .unwrap_or_default();

        let fs_meta = std::fs::metadata(path)
            .with_context(|| format!("Cannot stat {:?}", path))?;

        let mtime = fs_meta
            .modified()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();

        let base = TrackMetadata {
            id: TrackMetadata::id_from_path(path),
            path: path.to_path_buf(),
            media_type: classify_media_type(&ext),
            title: None,
            artist: None,
            album_artist: None,
            album: None,
            genre: None,
            year: None,
            track_number: None,
            disc_number: None,
            composer: None,
            comment: None,
            bpm: None,
            duration_secs: 0.0,
            sample_rate: None,
            bit_rate: None,
            channels: None,
            codec: None,
            artwork_data: None,
            artwork_mime: None,
            file_size_bytes: fs_meta.len(),
            mtime,
        };

        let result = match ext.as_str() {
            "mp3" => self.parse_mp3(path, base),
            "flac" => self.parse_flac(path, base),
            _ => self.parse_symphonia(path, base),
        };

        result.or_else(|_| self.parse_symphonia(path, TrackMetadata {
            id: TrackMetadata::id_from_path(path),
            path: path.to_path_buf(),
            media_type: classify_media_type(&ext),
            title: None,
            artist: None,
            album_artist: None,
            album: None,
            genre: None,
            year: None,
            track_number: None,
            disc_number: None,
            composer: None,
            comment: None,
            bpm: None,
            duration_secs: 0.0,
            sample_rate: None,
            bit_rate: None,
            channels: None,
            codec: None,
            artwork_data: None,
            artwork_mime: None,
            file_size_bytes: fs_meta.len(),
            mtime,
        }))
    }

    fn parse_mp3(&self, path: &Path, mut base: TrackMetadata) -> Result<TrackMetadata> {
        let tag = id3::Tag::read_from_path(path)
            .with_context(|| format!("id3 failed for {:?}", path))?;

        base.title = tag.title().map(str::to_owned);
        base.artist = tag.artist().map(str::to_owned);
        base.album = tag.album().map(str::to_owned);
        base.album_artist = tag.album_artist().map(str::to_owned);
        base.genre = tag.genre().map(str::to_owned);
        base.year = tag.year().map(|y| y as u32);
        base.track_number = tag.track();
        base.disc_number = tag.disc();
        base.composer = tag
            .frames()
            .find(|f| f.id() == "TCOM")
            .and_then(|f| f.content().text())
            .map(str::to_owned);
        base.bpm = tag
            .frames()
            .find(|f| f.id() == "TBPM")
            .and_then(|f| f.content().text())
            .and_then(|s| s.parse().ok());

        // Embedded artwork
        if let Some(picture) = tag.pictures().next() {
            base.artwork_mime = Some(picture.mime_type.clone());
            base.artwork_data = Some(picture.data.clone());
        }

        // Duration via symphonia fallback (id3 doesn't expose audio properties)
        base = self.enrich_with_symphonia_properties(path, base)?;

        debug!("Parsed MP3: {:?}", path);
        Ok(base)
    }

    fn parse_flac(&self, path: &Path, mut base: TrackMetadata) -> Result<TrackMetadata> {
        let tag = metaflac::Tag::read_from_path(path)
            .with_context(|| format!("metaflac failed for {:?}", path))?;

        let comments = tag.vorbis_comments();
        let get = |key: &str| -> Option<String> {
            comments
                .and_then(|c| c.get(key))
                .and_then(|v| v.first())
                .cloned()
        };

        base.title = get("TITLE");
        base.artist = get("ARTIST");
        base.album = get("ALBUM");
        base.album_artist = get("ALBUMARTIST");
        base.genre = get("GENRE");
        base.year = get("DATE").and_then(|d| d[..4.min(d.len())].parse().ok());
        base.track_number = get("TRACKNUMBER").and_then(|t| t.parse().ok());
        base.disc_number = get("DISCNUMBER").and_then(|d| d.parse().ok());
        base.composer = get("COMPOSER");
        base.bpm = get("BPM").and_then(|b| b.parse().ok());

        // Artwork from FLAC PICTURE block
        if let Some(picture) = tag.pictures().next() {
            base.artwork_mime = Some(picture.mime_type.clone());
            base.artwork_data = Some(picture.data.clone());
        }

        // Stream info for duration / sample rate
        if let Some(info) = tag.get_streaminfo() {
            base.sample_rate = Some(info.sample_rate);
            base.channels = Some(info.num_channels as u8);
            let samples = info.total_samples;
            if info.sample_rate > 0 && samples > 0 {
                base.duration_secs = samples as f64 / info.sample_rate as f64;
            }
        }

        debug!("Parsed FLAC: {:?}", path);
        Ok(base)
    }

    fn parse_symphonia(&self, path: &Path, mut base: TrackMetadata) -> Result<TrackMetadata> {
        use symphonia::core::io::MediaSourceStream;
        use symphonia::core::probe::Hint;
        use symphonia::core::formats::FormatOptions;
        use symphonia::core::meta::MetadataOptions;

        let file = std::fs::File::open(path)
            .with_context(|| format!("Cannot open {:?}", path))?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .with_context(|| format!("Symphonia probe failed for {:?}", path))?;

        let mut format = probed.format;

        // Extract tags from Symphonia
        if let Some(metadata) = format.metadata().current() {
            for tag in metadata.tags() {
                match tag.std_key {
Some(symphonia::core::meta::StandardTagKey::TrackTitle) => {
                         base.title = Some(tag.value.to_string());
                     }
Some(symphonia::core::meta::StandardTagKey::Artist) => {
                         base.artist = Some(tag.value.to_string());
                     }
Some(symphonia::core::meta::StandardTagKey::Album) => {
                         base.album = Some(tag.value.to_string());
                     }
Some(symphonia::core::meta::StandardTagKey::AlbumArtist) => {
                         base.album_artist = Some(tag.value.to_string());
                     }
Some(symphonia::core::meta::StandardTagKey::Genre) => {
                         base.genre = Some(tag.value.to_string());
                     }
Some(symphonia::core::meta::StandardTagKey::Date) => {
                         base.year = tag.value.to_string()
                             .get(0..4.min(tag.value.to_string().len()))
                             .and_then(|s| s.parse().ok());
                     }
Some(symphonia::core::meta::StandardTagKey::TrackNumber) => {
                         base.track_number = tag.value.to_string()
                             .split('/')
                             .next()
                             .and_then(|s| s.parse().ok());
                     }
                    _ => {}
                }
            }

            // Artwork
            if let Some(visual) = metadata.visuals().first() {
                base.artwork_mime = Some(visual.media_type.clone());
                base.artwork_data = Some(visual.data.to_vec());
            }
        }

        // Duration from first track
        if let Some(track) = format.default_track() {
            let params = &track.codec_params;
            base.sample_rate = params.sample_rate;
            base.channels = params.channels.map(|c| c.count() as u8);
            base.codec = Some(format!("{:?}", params.codec));
            if let (Some(n_frames), Some(sr)) = (params.n_frames, params.sample_rate) {
                base.duration_secs = n_frames as f64 / sr as f64;
            }
        }

        debug!("Parsed via Symphonia: {:?}", path);
        Ok(base)
    }

    fn enrich_with_symphonia_properties(&self, path: &Path, base: TrackMetadata) -> Result<TrackMetadata> {
        // Parse only stream properties (duration, bitrate, sample rate) using symphonia
        // without overwriting already-parsed tags
        use symphonia::core::io::MediaSourceStream;
        use symphonia::core::probe::Hint;
        use symphonia::core::formats::FormatOptions;
        use symphonia::core::meta::MetadataOptions;

        let file = match std::fs::File::open(path) {
            Ok(f) => f,
            Err(_) => return Ok(base),
        };
        let mss = MediaSourceStream::new(Box::new(file), Default::default());
        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let mut enriched = base;
        if let Ok(probed) = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        {
            let format = probed.format;
            if let Some(track) = format.default_track() {
                let params = &track.codec_params;
                enriched.sample_rate = enriched.sample_rate.or(params.sample_rate);
                enriched.channels = enriched.channels.or(params.channels.map(|c| c.count() as u8));
                enriched.codec = enriched.codec.or_else(|| Some(format!("{:?}", params.codec)));
                if enriched.duration_secs == 0.0 {
                    if let (Some(n_frames), Some(sr)) = (params.n_frames, params.sample_rate) {
                        enriched.duration_secs = n_frames as f64 / sr as f64;
                    }
                }
            }
        }

        Ok(enriched)
    }
}

impl Default for MetadataParser {
    fn default() -> Self {
        Self::new()
    }
}

fn classify_media_type(ext: &str) -> MediaType {
    match ext {
        "m4b" => MediaType::Audiobook,
        "mp4" | "m4v" | "mkv" | "avi" | "mov" | "webm" | "flv" | "ts" => MediaType::Video,
        _ => MediaType::Audio,
    }
}

// Minimal hex helper used for ID generation
mod hex {
    pub fn encode(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{:02x}", b)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_classify_media_type() {
        assert_eq!(classify_media_type("mp3"), MediaType::Audio);
        assert_eq!(classify_media_type("m4b"), MediaType::Audiobook);
        assert_eq!(classify_media_type("mkv"), MediaType::Video);
    }

    #[test]
    fn test_display_title_fallback_to_filename() {
        let meta = TrackMetadata {
            id: "abc".to_owned(),
            path: PathBuf::from("/music/my track.mp3"),
            media_type: MediaType::Audio,
            title: None,
            artist: None,
            album_artist: None,
            album: None,
            genre: None,
            year: None,
            track_number: None,
            disc_number: None,
            composer: None,
            comment: None,
            bpm: None,
            duration_secs: 0.0,
            sample_rate: None,
            bit_rate: None,
            channels: None,
            codec: None,
            artwork_data: None,
            artwork_mime: None,
            file_size_bytes: 0,
            mtime: 0,
        };
        assert_eq!(meta.display_title(), "my track");
    }

    #[test]
    fn test_display_title_uses_tag_when_present() {
        let mut meta = TrackMetadata {
            id: "abc".to_owned(),
            path: PathBuf::from("/music/01.mp3"),
            media_type: MediaType::Audio,
            title: Some("Comfortably Numb".to_owned()),
            artist: None,
            album_artist: None,
            album: None,
            genre: None,
            year: None,
            track_number: None,
            disc_number: None,
            composer: None,
            comment: None,
            bpm: None,
            duration_secs: 0.0,
            sample_rate: None,
            bit_rate: None,
            channels: None,
            codec: None,
            artwork_data: None,
            artwork_mime: None,
            file_size_bytes: 0,
            mtime: 0,
        };
        assert_eq!(meta.display_title(), "Comfortably Numb");
    }
}
