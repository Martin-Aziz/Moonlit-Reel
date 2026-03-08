# Moonlit Reel

> The definitive offline-first media experience for macOS — blazing-fast library management, world-class audiobook player, and real-time audio processing. No subscriptions. No cloud dependency. No compromises.

---

## The Idea

Moonlit Reel is a hyper-premium macOS media player built for serious media consumers who own their content. It indexes thousands of files in seconds, navigates audiobooks with chapter awareness, processes audio in real time through a parametric equalizer and effects chain, and plays back video with hardware acceleration — entirely offline.

---

## Technical Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  SwiftUI Presentation Layer (macOS 26.2+)                      │
│  NavigationSplitView · AVAudioEngine tap · Metal Visualizer    │
├────────────────────────────────────────────────────────────────┤
│  Swift Service Layer                                           │
│  LibraryService · PlayerService · AudiobookService             │
│  SearchService · MetadataService                               │
├────────────────────────────────────────────────────────────────┤
│  Rust Core Engine (static library via cbindgen FFI)            │
│  Scanner (rayon+walkdir) · Tantivy Search · sled KV            │
│  Symphonia Decoder · Effects Chain · Audiobook Engine          │
└────────────────────────────────────────────────────────────────┘
```

### Bounded Contexts

| Context | Responsibility | Primary Owner |
|---------|---------------|---------------|
| **Library** | File scanning, metadata, indexing | Rust scanner + Swift LibraryService |
| **Playback** | Audio/video output, effects, gapless | AVAudioEngine + Rust effects |
| **Search** | Full-text, faceted, fuzzy search | Rust Tantivy |
| **Audiobook** | Chapter detection, progress, bookmarks | Rust audiobook + Swift AudiobookService |
| **Persistence** | Library state, positions, playlists | Rust sled |
| **Presentation** | UI, navigation, visualizer | SwiftUI + Metal |

### Data Flow

```
User adds folder
     ↓
NSOpenPanel → Security-Scoped Bookmark (persisted)
     ↓
Rust scanner walks dir (rayon parallel) → metadata → sled KV
     ↓
Tantivy search index built/updated
     ↓
LibraryService publishes diff via AsyncStream
     ↓
SwiftUI library views update incrementally
```

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Language (UI) | Swift | 6.0 |
| UI Framework | SwiftUI | macOS 26.2 |
| Audio Engine | AVAudioEngine | native |
| Video Engine | AVPlayer + AVFoundation | native |
| Language (core) | Rust | 1.78 stable |
| Parallel scanning | rayon + walkdir | 1.10 / 2.5 |
| Audio decode | symphonia | 0.5 |
| Full-text search | tantivy | 0.22 |
| Persistence | sled | 0.34 |
| Audio I/O (Rust) | cpal + rodio | 0.15 / 0.19 |
| Resampling | rubato | 0.15 |
| FFI generation | cbindgen | 0.26 |
| Async runtime | tokio | 1.x |
| Build | Cargo + Xcode | latest |

---

## Quick Start

### Prerequisites

- macOS 26.2 (Tahoe) or later
- Xcode 26.2 or later
- Rust toolchain (stable): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- `cbindgen`: `cargo install cbindgen`

### Installation

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd "Moonlit Reel"

# 2. Run the setup script (installs Rust, builds the core library)
chmod +x scripts/setup.sh
./scripts/setup.sh

# 3. Open in Xcode and build
open "Moonlit Reel.xcodeproj"
```

> **First time Xcode setup (required once):**
> In Xcode → "Moonlit Reel" target → Build Phases → "+" → New Run Script Phase
> Script: `bash "${SRCROOT}/scripts/build_rust.sh"`
> Uncheck "Based on dependency analysis"
> Input files: `$(SRCROOT)/MoonlitReelCore/src/**`

### Running Tests

```bash
# Rust unit + integration tests
cd MoonlitReelCore
cargo test

# Swift tests (in Xcode)
# Product → Test (⌘U)
```

---

## Key Features

### MVP Features
- **Blazing-fast library scanner** — 50,000 files in < 3 seconds on M1 Mac via Rust/rayon
- **Gapless + crossfade playback** — Zero-gap album playback with adjustable crossfade
- **10-Band Parametric EQ** — Real-time biquad filters, 20 presets + manual nodes
- **Audiobook first-class support** — Folder import, chapter detection (M4B/CUE/filename), per-position resume, sleep timer, bookmarks
- **Tantivy-powered search** — Sub-50ms fuzzy search with `artist:radiohead year:>2000` syntax
- **Video playback** — Hardware-accelerated H.264/HEVC/ProRes + FFmpeg fallback for AV1/VP9
- **SRT subtitle rendering** — Parsed in Rust, rendered as SwiftUI overlay
- **Smart playlists** — BPM, last played, skip count, rating, path pattern rules
- **Real-time spectrum visualizer** — Metal-rendered 64-band FFT, waveform, and particle modes

### Bonus Features (shipped above MVP spec)
- **Speed + pitch control** — 0.5x–2.0x with rubato pitch preservation
- **ReplayGain 2.0** — Album and track normalization with configurable pre-amp
- **Convolution reverb** — IR file loading with room size/decay mix controls
- **Export playlist** — M3U, XSPF, JSON with relative paths option
- **Local HTTP remote control** — Optional axum server on `localhost:7177` for browser/phone control
- **Frame stepping** — Frame-accurate ±1 frame advance for video review

---

## Architecture Decisions

See [DECISIONS.md](DECISIONS.md) and `docs/adr/` for full decision rationale.

| Decision | Alternatives | Rationale | Trade-offs |
|----------|-------------|-----------|------------|
| Rust static library | XPC subprocess, pure Swift | Sandbox-friendly, no IPC overhead | Manual Xcode run script setup required |
| AVAudioEngine for output | cpal full pipeline | HW acceleration, native tap for visualizer | Apple-proprietary; migration path documented |
| Tantivy for search | Core Spotlight, SQLite FTS5 | Offline-first, <50ms for 100k tracks | No daemon dependency; index rebuild needed on schema change |
| sled for KV | SQLite/Core Data | Zero-config, pure Rust, ACID-adjacent | Less tooling than SQLite; see DECISIONS.md |

---

## Future Improvements (Technical Debt)

See [DECISIONS.md#known-technical-debt](DECISIONS.md#known-technical-debt-prioritized) for full prioritized list.

1. **[High]** Migrate audio output to cpal for cross-platform portability
2. **[High]** Tantivy schema migration strategy
3. **[Medium]** ASS/SSA subtitle renderer
4. **[Medium]** iCloud BookMarks/Playlist sync via CloudKit
5. **[Low]** On-device mood analysis via `tract` ONNX model
6. **[Low]** RGB lighting sync via `hidapi`
