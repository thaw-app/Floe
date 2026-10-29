#!/usr/bin/env bash
# Builds Floe.xcodeproj and installs it as /Applications/Floe.app, then launches it.
# Regenerates the project from project.yml first when XcodeGen is installed.
#
# Usage:
#   ./scripts/devrun.sh              # Release
#   ./scripts/devrun.sh --debug      # Debug, for the debugger
#   ./scripts/devrun.sh --no-launch  # build and install only
#   ./scripts/devrun.sh --icloud     # signed as a release is, so settings sync works
#
# Signs with the first valid "Apple Development" certificate in the keychain, or the one named by
# FLOE_SIGN_IDENTITY, and ad hoc when there is none.
#
# --icloud uses the "Developer ID Application" certificate and the profile at FLOE_PROVISIONING_PROFILE
# (default ~/.config/floe/Floe_Developer_ID.provisionprofile), and syncs with iCloud's Production data.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
cd "$SCRIPT_DIR/.."

PROJECT="Floe.xcodeproj"
SCHEME="Floe"
CONFIG="Release"
APP_NAME="Floe"
DEST="/Applications/$APP_NAME.app"
BUNDLE_ID="org.thaw.floe"
DERIVED=".build/xcode"
LAUNCH=1
ICLOUD=0
PROFILE="${FLOE_PROVISIONING_PROFILE:-$HOME/.config/floe/Floe_Developer_ID.provisionprofile}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="Debug" ;;
        --release) CONFIG="Release" ;;
        --no-launch) LAUNCH=0 ;;
        --icloud) ICLOUD=1 ;;
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

# Built again when it is missing or older than its Rust sources or its header.
RUST_FRAMEWORK="Vendor/FloeRust/Frameworks/CFloeRust.xcframework"
if [[ ! -d "$RUST_FRAMEWORK" || -n "$(find Vendor/FloeRust/rust/src Vendor/FloeRust/rust/Cargo.toml Vendor/FloeRust/include -newer "$RUST_FRAMEWORK" -print -quit)" ]]; then
    say "Building the FloeRust xcframework…"
    ./scripts/build-rust.sh
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
# A Mac without Rust's Intel target builds the library for itself alone, and then the app is built so too.
if ! lipo -archs "$RUST_FRAMEWORK"/*/libfloe_rust.a | grep -q x86_64; then
    BUILD_ARGS+=(ONLY_ACTIVE_ARCH=YES)
fi

say "Building $CONFIG ($BUNDLE_ID)…"
xcodebuild "${BUILD_ARGS[@]}" build | { grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true; }
APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$APP" ]] || {
    echo "Build product not found: $APP" >&2
    exit 1
}

fail() {
    echo "$*" >&2
    exit 1
}

sign_for_icloud() {
    local identity work application team
    [[ -f "$PROFILE" ]] || fail "No provisioning profile at $PROFILE (set FLOE_PROVISIONING_PROFILE)."
    identity="${FLOE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ && !/CSSMERR/ && !found { print $2; found = 1 }')}"
    [[ -n "$identity" ]] || fail "No Developer ID Application certificate in the keychain."

    work=$(mktemp -d)
    # Removed however this ends, a refused profile included.
    trap "rm -rf '$work'" EXIT
    security cms -D -i "$PROFILE" >"$work/profile.plist"
    application=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$work/profile.plist")
    team=${application%%.*}
    # Checked before PlistBuddy sees them: a team identifier is ten capital letters and digits, and the
    # bundle identifier is letters, digits, dots and hyphens, so neither can end a command and start another.
    [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail "The profile's team, $team, is not a team identifier."
    [[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || fail "$BUNDLE_ID is not a bundle identifier."
    [[ "$application" == "$team.$BUNDLE_ID" ]] || fail "The profile is for $application, not $BUNDLE_ID."

    # What Xcode fills in when it signs with a profile: the key-value store's identifier, the app's
    # identifier, the team and the environment. A value set by key, not text replaced, so nothing in it is a pattern.
    cp Resources/Floe-iCloud.entitlements "$work/entitlements.plist"
    /usr/libexec/PlistBuddy \
        -c "Set :com.apple.developer.ubiquity-kvstore-identifier $application" \
        -c "Add :com.apple.application-identifier string $application" \
        -c "Add :com.apple.developer.team-identifier string $team" \
        -c "Add :com.apple.developer.icloud-container-environment string Production" "$work/entitlements.plist"
    # A variable added to the template later would reach the signature as written.
    if grep -qF "\$(" "$work/entitlements.plist"; then
        fail "Resources/Floe-iCloud.entitlements has a variable devrun.sh does not fill in."
    fi

    say "Signing for iCloud with the Developer ID certificate and $(basename "$PROFILE")…"
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    codesign --force --deep --timestamp=none --preserve-metadata=entitlements --sign "$identity" "$APP" 2>/dev/null
    # Not --deep: only the app itself may claim what the profile grants, never Bun or a helper inside it.
    codesign --force --timestamp=none --entitlements "$work/entitlements.plist" --sign "$identity" "$APP" 2>/dev/null
    codesign --verify --deep --strict "$APP"
}

# macOS ties a permission such as Accessibility to the signature. The build's ad hoc one changes every
# time, so each build would lose its grants; a development certificate keeps them.
if [[ "$ICLOUD" -eq 1 ]]; then
    sign_for_icloud
else
    IDENTITY="${FLOE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ && !/CSSMERR/ && !found { print $2; found = 1 }')}"
    if [[ -n "$IDENTITY" ]]; then
        say "Signing with a development certificate, so permissions survive the build…"
        codesign --force --deep --preserve-metadata=entitlements --sign "$IDENTITY" "$APP" 2>/dev/null
        codesign --verify --deep --strict "$APP"
    else
        say "No development certificate found: the build stays ad hoc, and macOS will ask for permissions again."
    fi
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
