#!/usr/bin/env bash
# Builds the fend-core-c Rust crate and packages it as CFendCore.xcframework.
#
# Usage:
#   ./scripts/build-fend.sh           # Build release xcframework
#   ./scripts/build-fend.sh --debug   # Build debug xcframework
#   ./scripts/build-fend.sh --clean   # Clean cargo artifacts first
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [[ -d "$SCRIPT_DIR/rust" ]]; then
    FEND_DIR="$SCRIPT_DIR"
    REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
elif [[ -d "$SCRIPT_DIR/../Vendor/FendCore/rust" ]]; then
    REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
    FEND_DIR="$REPO_ROOT/Vendor/FendCore"
else
    REPO_ROOT="$(pwd)"
    FEND_DIR="$REPO_ROOT/Vendor/FendCore"
fi
cd "$REPO_ROOT"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# Locate cargo
CARGO_BIN=""
for candidate in \
    "$(command -v cargo 2>/dev/null || true)" \
    "$HOME/.cargo/bin/cargo" \
    "$HOME/.local/bin/cargo" \
    /opt/homebrew/bin/cargo \
    /usr/local/bin/cargo; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        CARGO_BIN="$candidate"
        break
    fi
done

if [[ -z "$CARGO_BIN" ]]; then
    echo "error: cargo is not installed or not found in PATH" >&2
    exit 1
fi

export PATH="$(dirname "$CARGO_BIN"):$PATH"

MODE="release"
CARGO_FLAGS=("--release")
CLEAN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            MODE="debug"
            CARGO_FLAGS=()
            ;;
        --release)
            MODE="release"
            CARGO_FLAGS=("--release")
            ;;
        --clean)
            CLEAN=1
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

RUST_DIR="$FEND_DIR/rust"
INCLUDE_DIR="$FEND_DIR/include"
FRAMEWORKS_DIR="$FEND_DIR/Frameworks"
OUTPUT_XCFRAMEWORK="$FRAMEWORKS_DIR/CFendCore.xcframework"

if [[ $CLEAN -eq 1 ]]; then
    say "Cleaning cargo build in $RUST_DIR..."
    (cd "$RUST_DIR" && "$CARGO_BIN" clean)
fi

# With rustup, install the compiler rust-toolchain.toml names, with both targets. A newer rustup no
# longer does this by itself, and a build machine may have another version as its default.
if command -v rustup >/dev/null 2>&1; then
    CHANNEL=$(sed -n 's/^channel = "\(.*\)"$/\1/p' "$RUST_DIR/rust-toolchain.toml")
    say "Using Rust $CHANNEL..."
    rustup toolchain install "$CHANNEL" --profile minimal --no-self-update \
        --target aarch64-apple-darwin --target x86_64-apple-darwin >/dev/null
fi

say "Building fend-core-c ($MODE)..."

# Detect if x86_64 target stdlib is installed for universal binary. Asked from the crate's folder,
# where rust-toolchain.toml applies.
SUPPORTS_X86_64=0
X86_LIBDIR=$(cd "$RUST_DIR" && rustc --target x86_64-apple-darwin --print target-libdir 2>/dev/null || true)
if [[ -n "$X86_LIBDIR" && -d "$X86_LIBDIR" ]]; then
    SUPPORTS_X86_64=1
fi

TARGET_LIB=""
if [[ $SUPPORTS_X86_64 -eq 1 ]]; then
    say "Building universal macOS static library (arm64 + x86_64)..."
    (cd "$RUST_DIR" && "$CARGO_BIN" build --target aarch64-apple-darwin "${CARGO_FLAGS[@]}")
    (cd "$RUST_DIR" && "$CARGO_BIN" build --target x86_64-apple-darwin "${CARGO_FLAGS[@]}")
    
    mkdir -p "$RUST_DIR/target/universal-$MODE"
    UNIVERSAL_LIB="$RUST_DIR/target/universal-$MODE/libfend_core_c.a"
    lipo -create \
        "$RUST_DIR/target/aarch64-apple-darwin/$MODE/libfend_core_c.a" \
        "$RUST_DIR/target/x86_64-apple-darwin/$MODE/libfend_core_c.a" \
        -output "$UNIVERSAL_LIB"
    TARGET_LIB="$UNIVERSAL_LIB"
else
    say "Building native host static library (aarch64-apple-darwin)..."
    (cd "$RUST_DIR" && "$CARGO_BIN" build --target aarch64-apple-darwin "${CARGO_FLAGS[@]}")
    TARGET_LIB="$RUST_DIR/target/aarch64-apple-darwin/$MODE/libfend_core_c.a"
fi

if [[ ! -f "$TARGET_LIB" ]]; then
    echo "error: expected build artifact not found at $TARGET_LIB" >&2
    exit 1
fi

say "Packaging CFendCore.xcframework..."
rm -rf "$OUTPUT_XCFRAMEWORK"
mkdir -p "$FRAMEWORKS_DIR"

xcodebuild -create-xcframework \
    -library "$TARGET_LIB" \
    -headers "$INCLUDE_DIR" \
    -output "$OUTPUT_XCFRAMEWORK"

say "Successfully created $OUTPUT_XCFRAMEWORK"
