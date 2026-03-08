#!/usr/bin/env bash
# build_rust.sh — Xcode Run Script Build Phase for Rust core library
#
# Add this script as a Run Script phase in Xcode targeting the app:
#   Build Phases → "+" → New Run Script Phase
#   Script: bash "${SRCROOT}/scripts/build_rust.sh"
#
# The script compiles the Rust static library and regenerates the C header,
# then copies the .a into ${BUILT_PRODUCTS_DIR} for the linker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$PROJECT_ROOT/MoonlitReelCore"
HEADER_DIR="$CORE_DIR/include"
HEADER_FILE="$HEADER_DIR/moonlit_reel_core.h"

# Determine Cargo profile
if [ "${CONFIGURATION}" = "Release" ]; then
    CARGO_PROFILE="release"
    CARGO_FLAGS="--release"
else
    CARGO_PROFILE="debug"
    CARGO_FLAGS=""
fi

source_cargo_env() {
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
}

# ── Compile for active architecture ─────────────────────────────────────────
compile_for_arch() {
    local arch="${1}"
    local rust_target
    case "$arch" in
        arm64)  rust_target="aarch64-apple-darwin" ;;
        x86_64) rust_target="x86_64-apple-darwin"  ;;
        *)      echo "Unknown arch: $arch"; exit 1 ;;
    esac

    echo "  Compiling for ${rust_target} (${CARGO_PROFILE})..."
    cd "$CORE_DIR"
    cargo build ${CARGO_FLAGS} --target "${rust_target}" 2>&1 | sed 's/^/    /'

    echo "${CORE_DIR}/target/${rust_target}/${CARGO_PROFILE}/libmoonlit_reel_core.a"
}

source_cargo_env

echo "==> Building Rust core (${CARGO_PROFILE})..."

# Build for all requested archs and lipo if needed
ARCHS_ARRAY=($ARCHS)
LIB_PATHS=()

for arch in "${ARCHS_ARRAY[@]}"; do
    lib_path=$(compile_for_arch "$arch")
    LIB_PATHS+=("$lib_path")
done

# Produce universal binary if building for multiple archs, else copy directly
OUTPUT_LIB="${BUILT_PRODUCTS_DIR}/libmoonlit_reel_core.a"

if [ "${#LIB_PATHS[@]}" -gt 1 ]; then
    echo "  Merging into universal binary..."
    lipo -create "${LIB_PATHS[@]}" -output "$OUTPUT_LIB"
else
    cp "${LIB_PATHS[0]}" "$OUTPUT_LIB"
fi

echo "  Library: $OUTPUT_LIB"

# ── Generate / refresh C header ─────────────────────────────────────────────
if command -v cbindgen &>/dev/null; then
    echo "  Refreshing C bridging header..."
    mkdir -p "$HEADER_DIR"
    cbindgen \
        --config "$CORE_DIR/cbindgen.toml" \
        --crate moonlit-reel-core \
        --output "$HEADER_FILE" \
        2>&1 | sed 's/^/    /'
else
    echo "  Warning: cbindgen not found — using existing header (run scripts/setup.sh to fix)"
fi

echo "==> Rust build complete."
