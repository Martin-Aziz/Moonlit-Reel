//! ffi.rs — C-compatible FFI layer exposed to Swift
//!
//! All public functions here are decorated with `#[no_mangle]` and
//! use `extern "C"` calling convention. cbindgen reads this file to
//! generate `moonlit_reel_core.h`.
//!
//! Ownership rules:
//! - Rust allocates; callers must free via the provided `mr_free_*` functions.
//! - UTF-8 strings are returned as null-terminated C strings.
//! - Opaque handles are raw Box pointers; callers must not dereference them.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint, c_double, c_ulong};
use std::path::PathBuf;
use std::sync::OnceLock;

use tracing::error;

use crate::db::Database;
use crate::scanner::{LibraryScanner, ScanEvent};
use crate::search::{SearchEngine, SearchResult};
use crate::audiobook::{Audiobook, AudiobookDetector};
use crate::subtitle::SubtitleTrack;

// ── Opaque handle types exposed to C/Swift ───────────────────────────────────

/// Opaque database handle allocated by `mr_database_open`.
pub struct MrDatabase(Database);
/// Opaque search engine handle allocated by `mr_search_open`.
pub struct MrSearch(SearchEngine);
/// Opaque subtitle track handle.
pub struct MrSubtitleTrack(SubtitleTrack);

// ── Result codes ─────────────────────────────────────────────────────────────

pub const MR_OK:    c_int = 0;
pub const MR_ERROR: c_int = -1;

// ── String / memory utilities ─────────────────────────────────────────────────

/// Free a C string previously allocated by any `mr_*` function returning `*mut c_char`.
///
/// # Safety
/// `ptr` must be a pointer returned by a `mr_*` function, or NULL.
#[no_mangle]
pub unsafe extern "C" fn mr_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Free a database handle.
///
/// # Safety
/// `handle` must be a non-null pointer returned by `mr_database_open`.
#[no_mangle]
pub unsafe extern "C" fn mr_database_free(handle: *mut MrDatabase) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

// ── Database ──────────────────────────────────────────────────────────────────

/// Open the sled database at `data_dir`.
///
/// Returns a non-null opaque handle on success, or NULL on failure.
/// Caller must free with `mr_database_free`.
///
/// # Safety
/// `data_dir` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn mr_database_open(data_dir: *const c_char) -> *mut MrDatabase {
    let path = match c_str_to_path(data_dir) {
        Some(p) => p,
        None => {
            error!("mr_database_open: null or invalid path");
            return std::ptr::null_mut();
        }
    };
    match Database::open(&path) {
        Ok(db) => Box::into_raw(Box::new(MrDatabase(db))),
        Err(e) => {
            error!("mr_database_open failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Store a resume position. Returns `MR_OK` or `MR_ERROR`.
///
/// # Safety
/// `handle` and `item_id` must be non-null valid pointers.
#[no_mangle]
pub unsafe extern "C" fn mr_database_set_resume(
    handle: *const MrDatabase,
    item_id: *const c_char,
    position_secs: c_double,
) -> c_int {
    let db = guard_handle(handle);
    let id = c_str_to_string(item_id).unwrap_or_default();
    match db.set_resume(&id, position_secs) {
        Ok(_)  => MR_OK,
        Err(e) => { error!("set_resume error: {}", e); MR_ERROR }
    }
}

/// Get a resume position for `item_id`.
///
/// Writes to `*out_position_secs` and returns `MR_OK`, or returns `MR_ERROR` if not found.
///
/// # Safety
/// `handle`, `item_id`, and `out_position_secs` must be non-null.
#[no_mangle]
pub unsafe extern "C" fn mr_database_get_resume(
    handle: *const MrDatabase,
    item_id: *const c_char,
    out_position_secs: *mut c_double,
) -> c_int {
    let db = guard_handle(handle);
    let id = c_str_to_string(item_id).unwrap_or_default();
    match db.get_resume(&id) {
        Ok(Some(entry)) => {
            *out_position_secs = entry.position_secs;
            MR_OK
        }
        Ok(None) => MR_ERROR,
        Err(e) => { error!("get_resume error: {}", e); MR_ERROR }
    }
}

// ── Search ────────────────────────────────────────────────────────────────────

/// Open a Tantivy search index at `index_dir`.
///
/// # Safety
/// `index_dir` must be a valid null-terminated UTF-8 path.
#[no_mangle]
pub unsafe extern "C" fn mr_search_open(index_dir: *const c_char) -> *mut MrSearch {
    let path = match c_str_to_path(index_dir) {
        Some(p) => p,
        None => return std::ptr::null_mut(),
    };
    match SearchEngine::open(&path) {
        Ok(engine) => Box::into_raw(Box::new(MrSearch(engine))),
        Err(e) => {
            error!("mr_search_open failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Free a search handle.
///
/// # Safety
/// `handle` must be a non-null pointer from `mr_search_open`.
#[no_mangle]
pub unsafe extern "C" fn mr_search_free(handle: *mut MrSearch) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Search the library index.
///
/// Returns a null-terminated JSON array string like:
/// `[{"id":"...","title":"...","artist":"...","score":0.9}, ...]`
///
/// Caller must free with `mr_free_string`.
///
/// # Safety
/// `handle` and `query` must be non-null valid pointers.
#[no_mangle]
pub unsafe extern "C" fn mr_search_query(
    handle: *const MrSearch,
    query: *const c_char,
    limit: c_uint,
) -> *mut c_char {
    let engine = &guard_handle(handle).0;
    let query_str = c_str_to_string(query).unwrap_or_default();

    match engine.search(&query_str, limit as usize) {
        Ok(results) => {
            let json = results_to_json(&results);
            CString::new(json).map_or(std::ptr::null_mut(), |s| s.into_raw())
        }
        Err(e) => {
            error!("mr_search_query failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

// ── Subtitles ─────────────────────────────────────────────────────────────────

/// Load an SRT subtitle file.
///
/// # Safety
/// `path` must be a valid null-terminated UTF-8 path.
#[no_mangle]
pub unsafe extern "C" fn mr_subtitle_load_srt(path: *const c_char) -> *mut MrSubtitleTrack {
    let p = match c_str_to_path(path) {
        Some(p) => p,
        None => return std::ptr::null_mut(),
    };
    match SubtitleTrack::load_srt(&p) {
        Ok(track) => Box::into_raw(Box::new(MrSubtitleTrack(track))),
        Err(e) => {
            error!("mr_subtitle_load_srt failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Get the subtitle text active at `position_ms`, or NULL if none.
///
/// Returned string is valid until the next call or `mr_subtitle_free`.
/// Caller must NOT free the returned pointer.
///
/// # Safety
/// `handle` must be a non-null valid pointer from `mr_subtitle_load_srt`.
#[no_mangle]
pub unsafe extern "C" fn mr_subtitle_current_line(
    handle: *const MrSubtitleTrack,
    position_ms: c_ulong,
) -> *const c_char {
    let track = &guard_handle(handle).0;
    track
        .current_line(position_ms as u64)
        .and_then(|s| CString::new(s).ok())
        .map(|s| s.as_ptr())
        .unwrap_or(std::ptr::null())
}

/// Free a subtitle track handle.
///
/// # Safety
/// `handle` must be a non-null pointer from `mr_subtitle_load_srt`.
#[no_mangle]
pub unsafe extern "C" fn mr_subtitle_free(handle: *mut MrSubtitleTrack) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

// ── Library version / info ────────────────────────────────────────────────────

/// Returns a null-terminated version string. Caller must NOT free it.
#[no_mangle]
pub extern "C" fn mr_version() -> *const c_char {
    static VERSION: OnceLock<CString> = OnceLock::new();
    VERSION
        .get_or_init(|| CString::new(env!("CARGO_PKG_VERSION")).unwrap())
        .as_ptr()
}

// ── Internal helpers ──────────────────────────────────────────────────────────

unsafe fn c_str_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(str::to_owned)
}

unsafe fn c_str_to_path(ptr: *const c_char) -> Option<PathBuf> {
    c_str_to_string(ptr).map(PathBuf::from)
}

unsafe fn guard_handle<T>(ptr: *const T) -> &'static T {
    // Safety: callers are responsible for passing valid, live pointers.
    ptr.as_ref().expect("non-null FFI handle required")
}

fn results_to_json(results: &[SearchResult]) -> String {
    let items: Vec<String> = results
        .iter()
        .map(|r| {
            format!(
                r#"{{"id":{id},"path":{path},"title":{title},"artist":{artist},"album":{album},"score":{score:.4}}}"#,
                id     = json_str(&r.id),
                path   = json_str(&r.path),
                title  = json_str(&r.title),
                artist = json_str(&r.artist),
                album  = json_str(&r.album),
                score  = r.score,
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

fn json_str(s: &str) -> String {
    let escaped = s.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{}\"", escaped)
}
