#!/usr/bin/env bash
# Builds the floe-rust Rust crate and packages it as CFloeRust.xcframework.
#
# Usage:
#   ./scripts/build-rust.sh           # Build release xcframework
#   ./scripts/build-rust.sh --debug   # Build debug xcframework
#   ./scripts/build-rust.sh --clean   # Clean cargo artifacts first
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [[ -d "$SCRIPT_DIR/rust" ]]; then
    PACKAGE_DIR="$SCRIPT_DIR"
    REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
elif [[ -d "$SCRIPT_DIR/../Vendor/FloeRust/rust" ]]; then
    REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
    PACKAGE_DIR="$REPO_ROOT/Vendor/FloeRust"
else
    REPO_ROOT="$(pwd)"
    PACKAGE_DIR="$REPO_ROOT/Vendor/FloeRust"
fi
cd "$REPO_ROOT"

# The oldest macOS the app runs on, as project.yml has it. Without this the C parts of a crate are built
# for the macOS of the machine that builds them, and the linker warns on every one.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"

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

RUST_DIR="$PACKAGE_DIR/rust"
INCLUDE_DIR="$PACKAGE_DIR/include"
FRAMEWORKS_DIR="$PACKAGE_DIR/Frameworks"
OUTPUT_XCFRAMEWORK="$FRAMEWORKS_DIR/CFloeRust.xcframework"

if [[ $CLEAN -eq 1 ]]; then
    say "Cleaning cargo build in $RUST_DIR..."
    (cd "$RUST_DIR" && "$CARGO_BIN" clean)
fi

# With rustup, install the compiler rust-toolchain.toml names, with both targets. A newer rustup no
# longer does this by itself, and a build machine may have another version as its default.
if command -v rustup >/dev/null 2>&1; then
    CHANNEL=$(sed -n 's/^channel = "\(.*\)"$/\1/p' "$RUST_DIR/rust-toolchain.toml")
    if [[ -z "$CHANNEL" ]]; then
        echo "error: no channel found in $RUST_DIR/rust-toolchain.toml" >&2
        exit 1
    fi
    say "Using Rust $CHANNEL..."
    rustup toolchain install "$CHANNEL" --profile minimal --no-self-update \
        --target aarch64-apple-darwin --target x86_64-apple-darwin >/dev/null
fi

say "Building floe-rust ($MODE)..."

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
    UNIVERSAL_LIB="$RUST_DIR/target/universal-$MODE/libfloe_rust.a"
    lipo -create \
        "$RUST_DIR/target/aarch64-apple-darwin/$MODE/libfloe_rust.a" \
        "$RUST_DIR/target/x86_64-apple-darwin/$MODE/libfloe_rust.a" \
        -output "$UNIVERSAL_LIB"
    TARGET_LIB="$UNIVERSAL_LIB"
else
    # Without the other target's standard library, the library is built for this Mac alone.
    HOST_TRIPLE=$(cd "$RUST_DIR" && rustc -vV | awk '/^host:/ {print $2}')
    say "Building native host static library ($HOST_TRIPLE)..."
    (cd "$RUST_DIR" && "$CARGO_BIN" build --target "$HOST_TRIPLE" "${CARGO_FLAGS[@]}")
    TARGET_LIB="$RUST_DIR/target/$HOST_TRIPLE/$MODE/libfloe_rust.a"
fi

if [[ ! -f "$TARGET_LIB" ]]; then
    echo "error: expected build artifact not found at $TARGET_LIB" >&2
    exit 1
fi

say "Packaging CFloeRust.xcframework..."
rm -rf "$OUTPUT_XCFRAMEWORK"
mkdir -p "$FRAMEWORKS_DIR"

xcodebuild -create-xcframework \
    -library "$TARGET_LIB" \
    -headers "$INCLUDE_DIR" \
    -output "$OUTPUT_XCFRAMEWORK"

say "Successfully created $OUTPUT_XCFRAMEWORK"
