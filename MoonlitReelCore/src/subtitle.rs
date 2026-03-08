//! subtitle.rs — SRT subtitle parsing and timecode management
//!
//! Rust parses SRT files into typed `Subtitle` structs. Swift renders
//! them as an overlay via `SubtitleTrack.currentLine(at: position)`.

use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// A single subtitle cue.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Subtitle {
    pub index:     u32,
    pub start_ms:  u64,
    pub end_ms:    u64,
    pub text:      String,
}

/// A loaded subtitle track.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubtitleTrack {
    pub file_path: std::path::PathBuf,
    pub cues:      Vec<Subtitle>,
}

impl SubtitleTrack {
    /// Load and parse an SRT file.
    pub fn load_srt(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("Cannot read subtitle file {:?}", path))?;
        let cues = parse_srt(&content)
            .with_context(|| format!("Failed to parse SRT {:?}", path))?;
        Ok(Self {
            file_path: path.to_path_buf(),
            cues,
        })
    }

    /// Returns the active subtitle text at `position_ms`, or `None`.
    pub fn current_line(&self, position_ms: u64) -> Option<&str> {
        self.cues
            .iter()
            .find(|c| position_ms >= c.start_ms && position_ms < c.end_ms)
            .map(|c| c.text.as_str())
    }

    /// Returns the next subtitle after the current position (for pre-loading).
    pub fn next_line(&self, position_ms: u64) -> Option<&Subtitle> {
        self.cues.iter().find(|c| c.start_ms > position_ms)
    }
}

/// Parse SRT-formatted string into a list of `Subtitle` cues.
pub fn parse_srt(content: &str) -> Result<Vec<Subtitle>> {
    let mut cues = Vec::new();
    let mut blocks = content.split("\n\n");

    for block in &mut blocks {
        let block = block.trim();
        if block.is_empty() {
            continue;
        }
        if let Some(cue) = parse_srt_block(block) {
            cues.push(cue);
        }
    }

    // Sort by start time in case SRT is out of order
    cues.sort_by_key(|c| c.start_ms);
    Ok(cues)
}

fn parse_srt_block(block: &str) -> Option<Subtitle> {
    let mut lines = block.lines();

    // Line 1: sequence number
    let index: u32 = lines.next()?.trim().parse().ok()?;

    // Line 2: timecode  00:00:01,000 --> 00:00:04,500
    let timecode_line = lines.next()?;
    let (start_ms, end_ms) = parse_srt_timecode(timecode_line)?;

    // Remaining lines: text (may contain HTML tags for ASS fallback)
    let text: String = lines
        .map(|l| strip_html(l))
        .collect::<Vec<_>>()
        .join("\n");

    if text.trim().is_empty() {
        return None;
    }

    Some(Subtitle { index, start_ms, end_ms, text })
}

fn parse_srt_timecode(line: &str) -> Option<(u64, u64)> {
    let parts: Vec<&str> = line.splitn(2, " --> ").collect();
    if parts.len() != 2 {
        return None;
    }
    let start = tc_to_millis(parts[0].trim())?;
    let end   = tc_to_millis(parts[1].trim())?;
    Some((start, end))
}

/// Convert `HH:MM:SS,mmm` to milliseconds.
fn tc_to_millis(tc: &str) -> Option<u64> {
    // Accept both , and . as decimal separator
    let tc = tc.replace(',', ".");
    let parts: Vec<&str> = tc.splitn(2, ".").collect();
    let hms: Vec<&str> = parts[0].splitn(3, ":").collect();
    if hms.len() != 3 {
        return None;
    }
    let h: u64 = hms[0].parse().ok()?;
    let m: u64 = hms[1].parse().ok()?;
    let s: u64 = hms[2].parse().ok()?;
    let ms: u64 = parts.get(1).and_then(|x| x.parse().ok()).unwrap_or(0);
    Some(h * 3_600_000 + m * 60_000 + s * 1_000 + ms)
}

/// Strip basic HTML/SSA tags from subtitle text (<i>, <b>, <u>, {…}).
fn strip_html(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    let mut in_tag = false;
    let mut in_ssa = false;
    for ch in s.chars() {
        match ch {
            '<' => in_tag  = true,
            '>' => in_tag  = false,
            '{' => in_ssa  = true,
            '}' => in_ssa  = false,
            _   => if !in_tag && !in_ssa { result.push(ch); }
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_SRT: &str = "1\r\n00:00:01,000 --> 00:00:04,500\r\nHello, <i>world</i>!\r\n\r\n\
        2\r\n00:00:05,000 --> 00:00:08,000\r\nSecond line.\r\n";

    #[test]
    fn test_parse_srt_basic() {
        let cues = parse_srt(SAMPLE_SRT).unwrap();
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].start_ms, 1000);
        assert_eq!(cues[0].end_ms,   4500);
        assert_eq!(cues[0].text, "Hello, world!");
    }

    #[test]
    fn test_current_line_within_range() {
        let cues = parse_srt(SAMPLE_SRT).unwrap();
        let track = SubtitleTrack { file_path: std::path::PathBuf::new(), cues };
        assert_eq!(track.current_line(2000), Some("Hello, world!"));
        assert_eq!(track.current_line(4500), Some("Second line."));
        assert_eq!(track.current_line(9000), None);
    }

    #[test]
    fn test_tc_to_millis_parsing() {
        assert_eq!(tc_to_millis("00:00:01,000"), Some(1000));
        assert_eq!(tc_to_millis("01:02:03,456"), Some(3_723_456));
        assert_eq!(tc_to_millis("invalid"), None);
    }

    #[test]
    fn test_strip_html_removes_ssa_tags() {
        assert_eq!(strip_html("{\\an8}Hello"), "Hello");
        assert_eq!(strip_html("<b>Bold</b>"), "Bold");
    }
}
