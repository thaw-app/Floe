#!/usr/bin/env bash
# Builds Floe.xcodeproj and installs it as /Applications/Floe.app, then launches it.
# Regenerates the project from project.yml first when XcodeGen is installed.
#
# Usage:
#   ./scripts/devrun.sh              # Release
#   ./scripts/devrun.sh --debug      # Debug, for the debugger
#   ./scripts/devrun.sh --no-launch  # build and install only
#
# Signs with the first valid "Apple Development" certificate in the keychain, or the one named by
# FLOE_SIGN_IDENTITY, and ad hoc when there is none.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
cd "$SCRIPT_DIR/.."

PROJECT="Floe.xcodeproj"
SCHEME="Floe"
CONFIG="Release"
APP_NAME="Floe"
DEST="/Applications/$APP_NAME.app"
BUNDLE_ID="com.thaw.floe"
DERIVED=".build/xcode"
LAUNCH=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="Debug" ;;
        --release) CONFIG="Release" ;;
        --no-launch) LAUNCH=0 ;;
        -h | --help)
            awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$SCRIPT_PATH"
            exit 0
            ;;
        *)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# Matches the installed executable only, so a `swift run` copy, or a shell that
# merely mentions the path, is left alone.
RUNNING="^$DEST/Contents/MacOS/"
quit_running_app() {
    pgrep -f "$RUNNING" >/dev/null 2>&1 || return 0

    say "Quitting running '$APP_NAME'…"
    pkill -f "$RUNNING" 2>/dev/null || true
    for _ in {1..8}; do
        pgrep -f "$RUNNING" >/dev/null 2>&1 || return 0
        sleep 0.5
    done

    say "Force-killing leftover '$APP_NAME' processes…"
    pkill -9 -f "$RUNNING" 2>/dev/null || true
    sleep 1
}

command -v bun >/dev/null 2>&1 || {
    echo "bun is not installed (brew install bun)" >&2
    exit 1
}

say "Installing runtime dependencies…"
# No package here needs an install script, so none are allowed to run.
(cd runtime && bun install --ignore-scripts --frozen-lockfile >/dev/null 2>&1 || bun install --ignore-scripts >/dev/null)

if [[ ! -d "Vendor/FendCore/Frameworks/CFendCore.xcframework" ]]; then
    say "Building Fend Core xcframework…"
    ./scripts/build-fend.sh
fi

if command -v xcodegen >/dev/null 2>&1; then
    say "Regenerating $PROJECT from project.yml…"
    xcodegen generate --quiet
fi

BUILD_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIG"
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath "$DERIVED"
)

say "Building $CONFIG ($BUNDLE_ID)…"
xcodebuild "${BUILD_ARGS[@]}" build | { grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true; }
APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$APP" ]] || {
    echo "Build product not found: $APP" >&2
    exit 1
}

# macOS ties a permission such as Accessibility to the signature. The build's ad hoc one changes every
# time, so each build would lose its grants; a development certificate keeps them.
IDENTITY="${FLOE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | grep -v CSSMERR | head -1 | awk '{print $2}')}"
if [[ -n "$IDENTITY" ]]; then
    say "Signing with a development certificate, so permissions survive the build…"
    codesign --force --deep --preserve-metadata=entitlements --sign "$IDENTITY" "$APP" 2>/dev/null
    codesign --verify --deep --strict "$APP"
else
    say "No development certificate found: the build stays ad hoc, and macOS will ask for permissions again."
fi

quit_running_app

say "Installing to ${DEST}…"
rm -rf "$DEST"
ditto "$APP" "$DEST"

if [[ "$LAUNCH" -eq 1 ]]; then
    say "Launching…"
    open "$DEST"
    say "Running '$APP_NAME' ($CONFIG). Press ⌃⌥Space to toggle it; quit from its menu bar icon."
else
    say "Installed '$APP_NAME' ($CONFIG) to $DEST without launching."
fi
