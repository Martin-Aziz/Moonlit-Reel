#!/usr/bin/env bash
# setup.sh — One-time developer environment setup for Moonlit Reel
# Run once after cloning. Requires macOS with Xcode CLI tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> Moonlit Reel: developer environment setup"

# ── 1. Rust toolchain ──────────────────────────────────────────────────────
if ! command -v rustup &>/dev/null; then
    echo "  Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source "$HOME/.cargo/env"
else
    echo "  Rust toolchain found: $(rustc --version)"
    rustup update stable
fi

# Add universal macOS targets
echo "  Adding macOS targets..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin

# ── 2. cbindgen ─────────────────────────────────────────────────────────────
if ! command -v cbindgen &>/dev/null; then
    echo "  Installing cbindgen..."
    cargo install cbindgen
else
    echo "  cbindgen found: $(cbindgen --version)"
fi

# ── 3. Build Rust core for current architecture ──────────────────────────
echo "  Building MoonlitReelCore (debug)..."
cd "$PROJECT_ROOT/MoonlitReelCore"
cargo build 2>&1 | sed 's/^/    /'

# ── 4. Generate C header ────────────────────────────────────────────────
echo "  Generating C bridging header..."
mkdir -p "$PROJECT_ROOT/MoonlitReelCore/include"
cbindgen \
    --config "$PROJECT_ROOT/MoonlitReelCore/cbindgen.toml" \
    --crate moonlit-reel-core \
    --output "$PROJECT_ROOT/MoonlitReelCore/include/moonlit_reel_core.h" \
    2>&1 | sed 's/^/    /'

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open 'Moonlit Reel.xcodeproj' in Xcode"
echo "  2. Add Run Script build phase (REQUIRED — see README.md 'First time Xcode setup')"
echo "  3. Build and Run (⌘R)"
echo ""
