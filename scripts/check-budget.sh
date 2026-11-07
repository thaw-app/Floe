#!/usr/bin/env bash
# Fails when the launcher, drawn off screen with searches typed into it, holds more memory than the budget.
#
# Usage:
#   ./scripts/check-budget.sh <Floe binary> [megabytes]   # the budget is 100 MB unless given
set -euo pipefail

BINARY="${1:?usage: check-budget.sh <Floe binary> [megabytes]}"
LIMIT="${2:-100}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Forgets the LaunchServices entry the run made for a bundle built in the repository. A bare binary such as
# .build/debug/Floe makes none, and an installed app keeps its entry.
forget_bundle() {
    [[ "$BINARY" == *.app/Contents/MacOS/* ]] || return 0
    local bundle
    bundle="$(cd "${BINARY%.app/Contents/MacOS/*}.app" 2>/dev/null && pwd -P)" || return 0
    [[ "$bundle" == "$ROOT"/* ]] || return 0
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$bundle" >/dev/null 2>&1 \
        || echo "::warning::LaunchServices still has $bundle; run lsregister -u on it before deleting the build." >&2
}
trap forget_bundle EXIT

output="$("$BINARY" --bench-search 2>&1 || true)"
grep -E '^(FIRST RENDER|TYPE|FOOTPRINT)' <<<"$output" || true

footprint=$(sed -n 's/^FOOTPRINT \([0-9]*\).*/\1/p' <<<"$output")
if [[ -z "$footprint" ]]; then
    # No figure means the benchmark did not finish: a crash, or a machine that cannot draw the launcher.
    tail -n 5 <<<"$output" >&2
    echo "::error::The benchmark reported no footprint, so the memory budget could not be checked." >&2
    exit 1
fi
if ((footprint > LIMIT)); then
    echo "::error::The launcher holds ${footprint} MB, over the budget of ${LIMIT} MB." >&2
    exit 1
fi
echo "The launcher holds ${footprint} MB, within the budget of ${LIMIT} MB."
