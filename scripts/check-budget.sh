#!/usr/bin/env bash
# Fails when the launcher, drawn off screen with searches typed into it, holds more memory than the budget.
#
# Usage:
#   ./scripts/check-budget.sh <Floe binary> [megabytes]   # the budget is 100 MB unless given
set -euo pipefail

BINARY="${1:?usage: check-budget.sh <Floe binary> [megabytes]}"
LIMIT="${2:-100}"

output="$("$BINARY" --bench-search 2>&1 || true)"
# Forget the LaunchServices entry the run made for its bundle; a bare binary such as .build/debug/Floe makes none.
if [[ "$BINARY" == *.app/Contents/MacOS/* ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "${BINARY%%.app/Contents/MacOS/*}.app" >/dev/null 2>&1 || true
fi
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
