#!/usr/bin/env bash
# Makes the Bun a release embeds: Bun's Apple silicon and Intel builds in one file, so Floe's extensions run on both.
#
# Usage:
#   .github/actions/universal-bun/universal-bun.sh <output>
#
# Each download is checked against the SHA-256 pinned below before it is used. lipo keeps each half's own signature,
# Bun's Developer ID with the hardened runtime and the JIT entitlement, so nothing is signed again here.
set -euo pipefail

# Bump all three together, and the bun-version the workflows install for their own steps.
VERSION="1.4.3"
SHA256_AARCH64="80afd4c069b46a6fa8f3ec520bebc750a7843e4a8d5b9583d29ad436c00a3403"
SHA256_X64="62660e6438eb872278877acca77e1152d5d031324df368d4a81b428211489d2d"

OUTPUT="${1:?usage: universal-bun.sh <output>}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for arch in aarch64 x64; do
    archive="$work/bun-darwin-$arch.zip"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        "https://github.com/oven-sh/bun/releases/download/bun-v${VERSION}/bun-darwin-${arch}.zip" -o "$archive"
    expected="SHA256_$(tr '[:lower:]' '[:upper:]' <<<"$arch")"
    echo "${!expected}  $archive" | shasum -a 256 -c - >/dev/null
    ditto -x -k "$archive" "$work"
done

mkdir -p "$(dirname "$OUTPUT")"
lipo -create "$work/bun-darwin-aarch64/bun" "$work/bun-darwin-x64/bun" -output "$OUTPUT"
codesign --verify --strict "$OUTPUT"
echo "$OUTPUT: Bun $("$OUTPUT" --version), $(lipo -archs "$OUTPUT")"
