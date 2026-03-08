//! moonlit-reel-core: public Rust library root
//!
//! All FFI entry points live in `ffi.rs`. Internal modules are
//! `pub(crate)` so that cbindgen only surfaces the explicit C API.

pub mod db;
pub mod metadata;
pub mod scanner;
pub mod search;
pub mod audiobook;
pub mod effects;
pub mod subtitle;
pub mod ffi;

// Re-export domain types for intra-crate use
pub use metadata::TrackMetadata;
pub use scanner::{ScanEvent, LibraryScanner};
pub use search::SearchEngine;
pub use audiobook::{Audiobook, Chapter};
pub use db::Database;
