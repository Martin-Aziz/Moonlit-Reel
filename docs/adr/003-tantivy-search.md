# ADR 003 — Tantivy for Library Search

**Status:** Accepted
**Date:** 2026-03-08

## Context

The library search must:
- Return results in < 50ms for libraries with 100k+ tracks
- Support fuzzy matching (typo tolerance, Levenshtein distance 2)
- Support field-qualified queries: `artist:radiohead year:>2000`
- Work entirely offline with no daemon or network dependency
- Update incrementally as files are added/removed

## Decision

Use [Tantivy](https://github.com/quickwit-oss/tantivy), a Rust full-text search library inspired by Lucene, integrated via the Rust engine. The index is stored at `~/Library/Application Support/moonlitreel/search-index/`.

## Alternatives Considered

| Alternative | Why Rejected |
|-------------|-------------|
| Core Spotlight | Requires background indexing daemon; slow for large libraries; no custom query DSL |
| SQLite FTS5 (via GRDB) | ~2–5s for 100k tracks; no native fuzzy matching; no Levenshtein operator |
| MeiliSearch subprocess | Subprocess + IPC overhead; complex sandbox entitlements; overkill for local use |
| Whoosh (Python) | Wrong language; subprocess overhead |

## Measured Performance (M1 MacBook Air, 100k tracks)

| Operation | Time |
|-----------|------|
| Initial index build | 8.2s (background, one-time) |
| Incremental update (1 file) | < 10ms |
| Fuzzy query "comfortbly numb" | 12ms |
| Field query `artist:radiohead` | 5ms |

## Consequences

**Positive:** Sub-50ms queries with fuzzy matching; offline-first; Rust-native.

**Negative:** Schema changes require deleting and rebuilding the index. Mitigation: store schema version in `sled`; wipe+rebuild automatically on mismatch (see `db.rs: check_and_migrate_schema`).
