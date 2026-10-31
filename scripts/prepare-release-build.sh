#!/bin/sh
# Run by org-ci's build-macos-app.yml before it archives a release: what Floe's build phases and packages need that the
# runner doesn't have. Uses no secrets, and the job it runs in has no access to the identity that signs provenance.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

# The Bun that ships: Apple silicon and Intel in one file, pinned in the script. The Embed Runtime build phase takes
# BUN_PATH first.
bun="$RUNNER_TEMP/universal-bun/bun"
.github/actions/universal-bun/universal-bun.sh "$bun"
echo "BUN_PATH=$bun" >>"$GITHUB_ENV"

# Before anything is sent to Apple: Bun as its developers signed it (team 7FRXF46ZSN).
for arch in arm64 x86_64; do
    codesign -dvvv --arch "$arch" "$bun" 2>&1 | grep -q '^TeamIdentifier=7FRXF46ZSN$' || {
        echo "::error::Bun's $arch half is not signed by team 7FRXF46ZSN."
        exit 1
    }
done

# The Embed Runtime build phase fails without runtime/node_modules.
(cd runtime && "$bun" install --frozen-lockfile --ignore-scripts)

# The calculator's engine and the file index, compiled from Vendor/FloeRust/rust for every build that ships: nothing is
# cached or downloaded. The FloeRust package does not resolve without it.
./scripts/build-rust.sh
