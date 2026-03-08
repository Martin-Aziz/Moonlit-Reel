# Implementation Decisions & Assumptions

## Project Identity

**Product Name:** Moonlit Reel (shipped name)
**Codebase Alias:** Aura (internal engineering alias, spec name)
**Bundle ID:** `com.github.Martin-Aziz.moonlitreel.Moonlit-Reel`
**Target Platform:** macOS 26.2 (Tahoe) and later
**Language Stack:** Rust (core engine) + Swift 6 / SwiftUI (presentation)

---

## Assumptions Made

### 1. macOS Deployment Target
**Assumption:** macOS 26.2 (Tahoe, "macOS 2026") as shipped in Xcode 26.2.
**Rationale:** The Xcode project was created with Xcode 26.2 and `MACOSX_DEPLOYMENT_TARGET = 26.2`.
**If wrong:** Lower the deployment target in Build Settings and replace APIs that did not ship until Tahoe.

### 2. App Sandbox Strategy
**Assumption:** App Sandbox is enabled (`ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES = readonly`).
**Chosen approach:** Use `NSOpenPanel` + Security-Scoped Bookmarks to persist access to user-selected library folders across launches. Bookmarks are stored in UserDefaults keyed by resolved path.
**If wrong / Sandbox removed:** Remove Security-Scoped Bookmark boilerplate; use direct `FileManager` paths.

### 3. Audio Playback Engine
**Assumption:** AVFoundation `AVAudioEngine` is used for all real-time audio effects (EQ, reverb, compression), while `AVPlayer` handles video. Pure software decoding via Rust/Symphonia is used as fallback only for formats AVFoundation cannot handle.
**Rationale:** `AVAudioEngine` provides low-latency hardware-accelerated path on Apple Silicon with tap nodes for visualizer data. Rust/cpal could replace this, but the gap in ecosystem maturity vs. AVFoundation is not justified for an MVP.
**If Rust cpal preferred:** Replace `AVAudioEngine` graph with cpal output device, pipe PCM from Rust through Swift audio session.
**Trade-off:** Documented in TECHNICAL_DEBT.md #1.

### 4. Rust FFI Integration Strategy
**Assumption:** Rust compiles to a universal static library (`.a`) via Cargo, then linked into the app via an Xcode Run Script phase. `cbindgen` generates the C header consumed by a Swift Bridging Header.
**Rationale:** Static linking avoids sandbox code-signing complexity for a dylib, and no XPC subprocess is needed (simpler entitlement model).
**If wrong:** Convert to `cdylib`, code-sign separately, add `com.apple.security.cs.allow-dyld-environment-variables`.

### 5. Search Engine
**Assumption:** Tantivy (Rust) powers full-text search on the library, exposed to Swift via the C FFI layer. The Tantivy index lives in `~/Library/Application Support/com.github.Martin-Aziz.moonlitreel/search-index/`.
**Rationale:** Sub-50ms fuzzy search across 100k tracks is not achievable with Core Spotlight without indexing delays. Tantivy provides a self-contained, offline-first solution.

### 6. Persistence Layer
**Assumption:** `sled` embedded KV store (Rust side) holds library metadata cache, audiobook positions, playback history, and resume state. SwiftData is used only for lightweight UI preferences and window state.
**Rationale:** Sled provides ACID-ish properties with near-zero setup. Eliminates the need for a PostgreSQL process or SQLite bridging, keeping the app fully offline.

### 7. Smart Playlist AI / Mood Analysis
**Assumption:** Deferred to post-MVP. The architecture is prepared (Rust `candle`/`tract` dependency stub in Cargo.toml) but no actual model is bundled. A `MoodTag` enum is defined in the domain model for future compatibility.
**Rationale:** Bundling an ONNX model adds significant binary size and is not essential for day-one value delivery.

### 8. Remote Control / HTTP Server
**Assumption:** Local HTTP server (axum) is architecturally wired but disabled by default. Exposed via Settings → Developer Options.
**Rationale:** Power users may want remote control from a phone browser; enabling by default raises security questions without user education.

### 9. RGB Mood Lighting
**Assumption:** `hidapi` integration deferred to post-MVP. Stub interfaces present for future implementation.
**Rationale:** Requires USB HID entitlement negotiation and device-specific protocols; out of scope for MVP.

### 10. Video Subtitle Rendering
**Assumption:** SRT subtitles are parsed in Rust (tokio-based file I/O) and rendered as a SwiftUI `Text` overlay on `AVPlayerLayer`. ASS/SSA support is noted as post-MVP.
**Rationale:** SRT covers 90%+ of use cases. ASS/SSA require a full renderer (libass port) that is disproportionate effort for an MVP.

---

## Technology Choices

| Decision | Alternatives Considered | Rationale | Migration Path |
|----------|------------------------|-----------|----------------|
| **Rust static library via cbindgen** | Swift Package wrapping dylib; XPC subprocess; pure Swift | Static link is simplest for sandbox; pure Swift lacks sub-50ms parallel scanning | Abstract via `CoreEngine` protocol |
| **AVAudioEngine for effects** | cpal (Rust) full pipeline | Zero-config HW acceleration, tap node for visualizer, mature API | Replace graph with cpal node |
| **Tantivy (Rust) for search** | Core Spotlight; SQLite FTS5 | Offline-first, sub-50ms for 100k tracks, no background daemon dependency | Swap index directory; keep Swift API unchanged |
| **sled (Rust) for KV storage** | SQLite via rusqlite; RocksDB | Zero-config embedded, ACID-adjacent, pure Rust | Repository pattern abstracts sled; replace in `db.rs` |
| **NavigationSplitView** | Custom sidebar NSWindow | Native macOS adaptation, State Restoration support, free keyboard nav | N/A — native SwiftUI |
| **Security-Scoped Bookmarks** | Remove sandbox; entitlement extension | Required for sandbox read access to arbitrary user library locations | Expand entitlements for write access when needed |

---

## Deviations from Standard Patterns

1. **Swift `@Observable` Macro over ObservableObject:** macOS Tahoe fully supports Swift Observation; `ObservableObject` is legacy. All service classes use `@Observable`.
2. **Swift 6 Strict Concurrency:** `SWIFT_APPROACHABLE_CONCURRENCY = YES` is set in the project. Services are marked `@MainActor` where UI binding is required; background work runs in `Task.detached` with explicit `Sendable` conformances.
3. **No Combine in new code:** The project was generated with Swift 6 defaults. New reactive code uses `AsyncStream` and `for await` instead of Combine publishers for cleaner actor isolation.

---

## Known Technical Debt (Prioritized)

### High Priority
1. **Rust cpal full audio pipeline:** AVAudioEngine is excellent but Apple-proprietary. If cross-platform is ever desired, the audio output must migrate to cpal. **Impact:** All real-time effect processing. **Resolution:** Abstract via `AudioEngineProtocol`, implement cpal backend in `MoonlitReelCore`.
2. **cbindgen manual run:** Currently, the C header must be regenerated whenever the Rust FFI surface changes. **Resolution:** Add `cargo build --features generate-headers` step to Xcode Run Script.

### Medium Priority
3. **Tantivy index schema migrations:** Tantivy indexes are not schema-migratable; old indexes must be deleted and rebuilt. **Resolution:** Store schema version in sled; wipe+rebuild on mismatch.
4. **SRT-only subtitle support:** ASS/SSA subtitles render as plain text fallback. **Resolution:** Port libass or use a Rust SSA renderer.

### Low Priority
5. **ID3v2 APIC frame extraction in AVFoundation fall-through:** Artwork may not load for malformed ID3v2.2 tags. **Resolution:** Use `id3` Rust crate as fallback for artwork extraction.
6. **No iCloud Library sync:** Position bookmarks and playlists are local only. **Resolution:** Expose sled snapshot as CloudKit `CKAsset`.

---

## Architecture Decision Records

See `docs/adr/` for full ADRs:
- [001-rust-backend.md](docs/adr/001-rust-backend.md) — Why Rust for the engine layer
- [002-avfoundation-playback.md](docs/adr/002-avfoundation-playback.md) — Why AVFoundation for audio/video playback
- [003-tantivy-search.md](docs/adr/003-tantivy-search.md) — Why Tantivy over Core Spotlight
