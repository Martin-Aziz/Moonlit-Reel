//! audiobook.rs — Audiobook chapter detection, progress tracking, and bookmarks
//!
//! Detects audiobooks from M4B files, CUE sheets, and folder patterns.
//! Stores per-file resume positions in the sled database.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

use crate::metadata::TrackMetadata;

/// A chapter within an audiobook.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chapter {
    pub index:       u32,
    pub title:       String,
    pub start_secs:  f64,
    pub end_secs:    f64,
    pub file_path:   PathBuf,
    /// Byte offset within file (for M4B atoms)
    pub byte_offset: Option<u64>,
}

impl Chapter {
    pub fn duration_secs(&self) -> f64 {
        (self.end_secs - self.start_secs).max(0.0)
    }
}

/// A user-created position bookmark within an audiobook.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bookmark {
    pub id:           String,
    pub audiobook_id: String,
    pub chapter_index: u32,
    pub position_secs: f64,
    pub label:        String,
    pub created_at:   u64,
}

/// An audiobook as a whole — a collection of ordered chapters.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Audiobook {
    pub id:              String,
    pub title:           String,
    pub author:          String,
    pub narrator:        Option<String>,
    pub folder_path:     PathBuf,
    pub chapters:        Vec<Chapter>,
    pub total_duration:  f64,
    /// Computed cumulative resume: which chapter + position we last left off at
    pub resume_chapter:  u32,
    pub resume_position: f64,
    pub bookmarks:       Vec<Bookmark>,
    pub artwork_data:    Option<Vec<u8>>,
    pub artwork_mime:    Option<String>,
}

impl Audiobook {
    /// Overall progress as a value 0.0–1.0.
    pub fn progress_fraction(&self) -> f64 {
        if self.total_duration <= 0.0 {
            return 0.0;
        }
        let elapsed = self.elapsed_secs();
        (elapsed / self.total_duration).clamp(0.0, 1.0)
    }

    /// Total elapsed seconds taking all completed chapters into account.
    pub fn elapsed_secs(&self) -> f64 {
        let completed: f64 = self.chapters
            .iter()
            .take(self.resume_chapter as usize)
            .map(|c| c.duration_secs())
            .sum();
        completed + self.resume_position
    }

    /// Remaining time in seconds.
    pub fn remaining_secs(&self) -> f64 {
        (self.total_duration - self.elapsed_secs()).max(0.0)
    }
}

/// Detects whether a directory or single file is an audiobook.
pub struct AudiobookDetector;

impl AudiobookDetector {
    pub fn new() -> Self {
        Self
    }

    /// Attempt to build an `Audiobook` from a path (file or directory).
    ///
    /// Returns `None` if the path does not look like an audiobook.
    pub fn detect(&self, path: &Path) -> Option<Audiobook> {
        if path.is_file() {
            self.detect_single_file(path)
        } else if path.is_dir() {
            self.detect_folder(path)
        } else {
            None
        }
    }

    fn detect_single_file(&self, path: &Path) -> Option<Audiobook> {
        let ext = path.extension()?.to_str()?.to_lowercase();
        match ext.as_str() {
            "m4b" => self.parse_m4b(path).ok(),
            _ => None,
        }
    }

    fn detect_folder(&self, dir: &Path) -> Option<Audiobook> {
        // Heuristic: folder contains only audio files (mp3/m4a) with ordered names
        // and either a .cue file or track count > 2
        let mut audio_files: Vec<PathBuf> = std::fs::read_dir(dir)
            .ok()?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_file())
            .filter(|p| {
                matches!(
                    p.extension().and_then(|e| e.to_str()).map(|e| e.to_lowercase()).as_deref(),
                    Some("mp3" | "m4a" | "aac" | "flac" | "ogg" | "opus" | "wav")
                )
            })
            .collect();

        if audio_files.len() < 2 {
            return None;
        }

        // Sort by filename (natural sort approximation)
        audio_files.sort_by(|a, b| {
            natord_compare(
                a.file_name().unwrap_or_default().to_string_lossy().as_ref(),
                b.file_name().unwrap_or_default().to_string_lossy().as_ref(),
            )
        });

        // Check for CUE sheet
        let cue_file = std::fs::read_dir(dir)
            .ok()?
            .filter_map(|e| e.ok())
            .find(|e| e.path().extension().and_then(|x| x.to_str()) == Some("cue"))
            .map(|e| e.path());

        let chapters = if let Some(cue) = cue_file {
            self.parse_cue(&cue, &audio_files).unwrap_or_else(|_| {
                chapters_from_files(&audio_files)
            })
        } else {
            chapters_from_files(&audio_files)
        };

        let total_duration: f64 = chapters.iter().map(|c| c.duration_secs()).sum();
        let folder_name = dir
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();

        let id = blake3_hash_str(dir.to_string_lossy().as_ref());

        Some(Audiobook {
            id,
            title: folder_name.clone(),
            author: String::new(),
            narrator: None,
            folder_path: dir.to_path_buf(),
            chapters,
            total_duration,
            resume_chapter: 0,
            resume_position: 0.0,
            bookmarks: vec![],
            artwork_data: None,
            artwork_mime: None,
        })
    }

    fn parse_m4b(&self, path: &Path) -> Result<Audiobook> {
        // M4B is an MP4 container. Use symphonia to extract chapter markers (chpl atoms).
        use symphonia::core::formats::FormatOptions;
        use symphonia::core::io::MediaSourceStream;
        use symphonia::core::meta::MetadataOptions;
        use symphonia::core::probe::Hint;

        let file = std::fs::File::open(path)?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());
        let mut hint = Hint::new();
        hint.with_extension("m4b");

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .context("Symphonia probe failed")?;

        let format = probed.format;

        let mut title = path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        let mut author = String::new();
        let mut artwork_data = None;
        let mut artwork_mime = None;

        if let Some(meta) = format.metadata().current() {
            for tag in meta.tags() {
                match tag.std_key {
                    Some(symphonia::core::meta::StandardTagKey::TrackTitle) => {
                        title = tag.value.to_string().unwrap_or(title.clone());
                    }
                    Some(symphonia::core::meta::StandardTagKey::Artist) => {
                        author = tag.value.to_string().unwrap_or_default();
                    }
                    _ => {}
                }
            }
            if let Some(visual) = meta.visuals().first() {
                artwork_mime = Some(visual.media_type.clone());
                artwork_data = Some(visual.data.to_vec());
            }
        }

        // Fallback: single chapter with full file duration
        let duration = if let Some(track) = format.default_track() {
            let p = &track.codec_params;
            p.n_frames.and_then(|n| p.sample_rate.map(|sr| n as f64 / sr as f64))
                .unwrap_or(0.0)
        } else {
            0.0
        };

        let chapters = vec![Chapter {
            index: 0,
            title: title.clone(),
            start_secs: 0.0,
            end_secs: duration,
            file_path: path.to_path_buf(),
            byte_offset: None,
        }];

        let id = blake3_hash_str(path.to_string_lossy().as_ref());

        Ok(Audiobook {
            id,
            title,
            author,
            narrator: None,
            folder_path: path.parent().unwrap_or(Path::new("/")).to_path_buf(),
            chapters,
            total_duration: duration,
            resume_chapter: 0,
            resume_position: 0.0,
            bookmarks: vec![],
            artwork_data,
            artwork_mime,
        })
    }

    fn parse_cue(&self, cue_path: &Path, audio_files: &[PathBuf]) -> Result<Vec<Chapter>> {
        let content = std::fs::read_to_string(cue_path)?;
        let mut chapters = Vec::new();
        let mut current_title = String::new();
        let mut current_start: f64 = 0.0;
        let mut chapter_index: u32 = 0;

        for line in content.lines() {
            let line = line.trim();
            if let Some(rest) = line.strip_prefix("TITLE ") {
                current_title = rest.trim_matches('"').to_owned();
            } else if let Some(rest) = line.strip_prefix("INDEX 01 ") {
                // Parse MM:SS:FF timecode
                if let Some(secs) = parse_cue_time(rest) {
                    if chapter_index > 0 {
                        if let Some(last) = chapters.last_mut() {
                            let c: &mut Chapter = last;
                            c.end_secs = secs;
                        }
                    }
                    let file = audio_files.first().cloned().unwrap_or_default();
                    chapters.push(Chapter {
                        index: chapter_index,
                        title: std::mem::take(&mut current_title),
                        start_secs: secs,
                        end_secs: 0.0,
                        file_path: file,
                        byte_offset: None,
                    });
                    chapter_index += 1;
                    current_start = secs;
                }
            }
        }

        Ok(chapters)
    }
}

impl Default for AudiobookDetector {
    fn default() -> Self {
        Self::new()
    }
}

fn chapters_from_files(files: &[PathBuf]) -> Vec<Chapter> {
    files
        .iter()
        .enumerate()
        .map(|(i, path)| Chapter {
            index: i as u32,
            title: path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned(),
            start_secs: 0.0,
            end_secs: 0.0,  // Filled in by metadata parser
            file_path: path.clone(),
            byte_offset: None,
        })
        .collect()
}

fn parse_cue_time(s: &str) -> Option<f64> {
    // Cue format: MM:SS:FF (frames at 75fps)
    let parts: Vec<&str> = s.trim().splitn(3, ':').collect();
    if parts.len() != 3 {
        return None;
    }
    let mm: f64 = parts[0].parse().ok()?;
    let ss: f64 = parts[1].parse().ok()?;
    let ff: f64 = parts[2].parse().ok()?;
    Some(mm * 60.0 + ss + ff / 75.0)
}

fn natord_compare(a: &str, b: &str) -> std::cmp::Ordering {
    // Simple natural ordering: compare leading numeric run numerically
    let extract = |s: &str| -> (u64, &str) {
        let num_end = s.find(|c: char| !c.is_ascii_digit()).unwrap_or(s.len());
        let num: u64 = s[..num_end].parse().unwrap_or(0);
        (num, &s[num_end..])
    };
    let (an, ar) = extract(a);
    let (bn, br) = extract(b);
    an.cmp(&bn).then_with(|| ar.cmp(br))
}

fn blake3_hash_str(s: &str) -> String {
    let hash = blake3::hash(s.as_bytes());
    hash.to_hex().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cue_time() {
        assert_eq!(parse_cue_time("00:00:00"), Some(0.0));
        assert!((parse_cue_time("01:30:00").unwrap() - 90.0).abs() < 0.01);
        // 75 frames = 1 second
        assert!((parse_cue_time("00:00:75").unwrap() - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_audiobook_progress() {
        let book = Audiobook {
            id: "x".into(),
            title: "Test".into(),
            author: "Author".into(),
            narrator: None,
            folder_path: PathBuf::from("/"),
            chapters: vec![
                Chapter { index: 0, title: "Ch1".into(), start_secs: 0.0, end_secs: 600.0,
                          file_path: PathBuf::new(), byte_offset: None },
                Chapter { index: 1, title: "Ch2".into(), start_secs: 0.0, end_secs: 600.0,
                          file_path: PathBuf::new(), byte_offset: None },
            ],
            total_duration: 1200.0,
            resume_chapter: 1,   // Partway into chapter 2
            resume_position: 300.0,
            bookmarks: vec![],
            artwork_data: None,
            artwork_mime: None,
        };
        // Elapsed = 600 (ch1 done) + 300 (ch2 position) = 900
        assert!((book.elapsed_secs() - 900.0).abs() < 0.001);
        assert!((book.progress_fraction() - 0.75).abs() < 0.001);
        assert!((book.remaining_secs() - 300.0).abs() < 0.001);
    }
}
