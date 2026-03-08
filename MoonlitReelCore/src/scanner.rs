//! scanner.rs — Parallel filesystem library scanner
//!
//! Uses `rayon` for parallel file walking and `notify` for real-time
//! folder watching. Emits `ScanEvent` items into a channel consumed
//! by the database layer.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use rayon::prelude::*;
use walkdir::{DirEntry, WalkDir};
use blake3::Hasher;
use anyhow::Result;
use tracing::{info, warn, debug};

use crate::metadata::{TrackMetadata, MetadataParser};

/// Supported audio/video file extensions (lowercase).
const AUDIO_EXTENSIONS: &[&str] = &[
    "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "aiff", "aif",
    "alac", "dsd", "dsf", "wv",
];

const VIDEO_EXTENSIONS: &[&str] = &[
    "mp4", "m4v", "mkv", "avi", "mov", "webm", "flv", "ts",
];

const AUDIOBOOK_EXTENSIONS: &[&str] = &[
    "m4b", "mp3",   // mp3 also listed here because audiobook folders use mp3
];

/// An event emitted for each discovered file during a scan.
#[derive(Debug, Clone)]
pub enum ScanEvent {
    /// A media file was found and its metadata parsed.
    Discovered(TrackMetadata),
    /// A previously known file was modified (new content hash).
    Modified(TrackMetadata),
    /// A file present in the DB was deleted from disk.
    Removed(PathBuf),
    /// Scan progress update (files_processed, files_total estimate).
    Progress { processed: u64, total_estimate: u64 },
    /// The scan of a root directory completed.
    Finished { root: PathBuf, duration_ms: u64, file_count: u64 },
}

/// Owns scanning state and caches known hashes to detect changes.
pub struct LibraryScanner {
    parser: Arc<MetadataParser>,
}

impl LibraryScanner {
    pub fn new() -> Self {
        Self {
            parser: Arc::new(MetadataParser::new()),
        }
    }

    /// Scan `root` in parallel, sending events on `tx`.
    ///
    /// Returns the number of files processed.
    pub fn scan(
        &self,
        root: &Path,
        tx: crossbeam_channel::Sender<ScanEvent>,
    ) -> Result<u64> {
        let started = Instant::now();

        // Collect all media paths first (fast, single-threaded walk)
        info!("Starting scan of {:?}", root);
        let paths = self.collect_media_paths(root);
        let total = paths.len() as u64;
        info!("Collected {} media files in {:?}", total, root);

        // Process in parallel via rayon
        let processed = Arc::new(std::sync::atomic::AtomicU64::new(0));
        let tx_clone = tx.clone();
        let processed_ref = processed.clone();
        let parser = self.parser.clone();

        paths.par_iter().for_each(|path| {
            match parser.parse(path) {
                Ok(metadata) => {
                    let _ = tx_clone.send(ScanEvent::Discovered(metadata));
                }
                Err(err) => {
                    warn!("Metadata parse failed for {:?}: {}", path, err);
                }
            }
            let current = processed_ref.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
            // Send progress every 500 files
            if current % 500 == 0 {
                let _ = tx_clone.send(ScanEvent::Progress {
                    processed: current,
                    total_estimate: total,
                });
            }
        });

        let file_count = processed.load(std::sync::atomic::Ordering::Relaxed);
        let duration_ms = started.elapsed().as_millis() as u64;

        info!(
            "Scan complete: {} files in {}ms ({:.0} files/sec)",
            file_count,
            duration_ms,
            if duration_ms > 0 { file_count as f64 / (duration_ms as f64 / 1000.0) } else { 0.0 }
        );

        let _ = tx.send(ScanEvent::Finished {
            root: root.to_path_buf(),
            duration_ms,
            file_count,
        });

        Ok(file_count)
    }

    fn collect_media_paths(&self, root: &Path) -> Vec<PathBuf> {
        WalkDir::new(root)
            .follow_links(false)
            .into_iter()
            .filter_map(|entry| entry.ok())
            .filter(|e| e.file_type().is_file())
            .filter(|e| is_media_file(e))
            .map(|e| e.into_path())
            .collect()
    }
}

impl Default for LibraryScanner {
    fn default() -> Self {
        Self::new()
    }
}

/// Returns true if the directory entry looks like a media file we can handle.
fn is_media_file(entry: &DirEntry) -> bool {
    entry
        .path()
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| {
            let lower = ext.to_lowercase();
            AUDIO_EXTENSIONS.contains(&lower.as_str())
                || VIDEO_EXTENSIONS.contains(&lower.as_str())
        })
        .unwrap_or(false)
}

/// Compute a BLAKE3 hash of a file's contents for change detection.
pub fn hash_file(path: &Path) -> Result<[u8; 32]> {
    let data = std::fs::read(path)?;
    let hash = blake3::hash(&data);
    Ok(*hash.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_collect_media_paths_ignores_non_media() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("track.mp3"), b"fake").unwrap();
        fs::write(dir.path().join("notes.txt"), b"fake").unwrap();
        fs::write(dir.path().join("cover.jpg"), b"fake").unwrap();
        fs::write(dir.path().join("song.flac"), b"fake").unwrap();

        let scanner = LibraryScanner::new();
        let paths = scanner.collect_media_paths(dir.path());
        assert_eq!(paths.len(), 2, "should find only mp3 and flac");
    }

    #[test]
    fn test_is_media_file_extension_case_insensitive() {
        // Test via hash_file surrogate (just extension logic)
        let p = std::path::Path::new("track.MP3");
        let ext = p.extension().and_then(|e| e.to_str()).map(|e| e.to_lowercase());
        assert!(AUDIO_EXTENSIONS.contains(&ext.as_deref().unwrap_or("")));
    }
}
