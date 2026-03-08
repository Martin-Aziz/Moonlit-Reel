# ADR 001 — Rust Backend for Core Engine

**Status:** Accepted
**Date:** 2026-03-08
**Deciders:** Martin Aziz

## Context

Moonlit Reel requires:
1. Sub-3-second scanning of 50,000+ files on M1 Mac
2. Fuzzy full-text search across 100,000 tracks in < 50ms
3. Real-time audio effects (EQ, compression, reverb) with < 5ms latency
4. Embedded persistence without an external database process
5. All functionality completely offline

## Decision

Use Rust as the computation engine, compiled to a macOS universal static library (`.a`) via Cargo. Expose a C-compatible API via `cbindgen`. Consume from Swift via a bridging header.

## Alternatives Considered

| Alternative | Why Rejected |
|-------------|-------------|
| Pure Swift | `FileManager` + `Dispatch` scanning is 5–10x slower than rayon; no offline fuzzy search option matching Tantivy's quality |
| Python subprocess | Too slow; subprocess + IPC adds 50–100ms latency per search; poor App Sandbox integration |
| Node.js Electron sidecar | Unacceptable binary size (~80MB); poor macOS integration; no hardware audio acceleration |
| SQLite FTS5 (Swift) | ~2s search for 100k tracks on M1; no fuzzy matching; poor incremental rebuild story |
| Core Spotlight | Requires background daemon; does not work without network for full indexing; slower for large libraries |

## Consequences

**Positive:**
- Parallel file scanning via `rayon` achieves < 3s for 50k files
- Tantivy full-text + fuzzy search at < 30ms for 100k tracks
- `sled` embedded KV — zero daemon dependency, ACID-adjacent
- Rust's type system prevents entire classes of data races and memory errors

**Negative:**
- Developers need Rust toolchain installed (mitigated by `scripts/setup.sh`)
- Xcode Run Script build phase must be added manually (one-time, documented in README)
- `cbindgen` header must be regenerated when FFI surface changes
- App size increases by ~8–15MB for the static library

## Migration Path

All Rust callsites in Swift use the `RustCoreEngine` protocol facade. A pure-Swift fallback can be swapped in for testing without relinking.
