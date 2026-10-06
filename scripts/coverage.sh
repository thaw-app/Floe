#!/usr/bin/env bash
# Runs the Swift and runtime test suites with coverage and writes the reports
# SonarQube reads:
#   coverage/swift.xml          generic coverage for Sources/
#   coverage/runtime/lcov.info  lcov for runtime/
#
# Usage:
#   ./scripts/coverage.sh            # both suites
#   ./scripts/coverage.sh --summary  # also print line coverage per measured file
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)/.."

SUMMARY=0
[[ "${1:-}" == "--summary" ]] && SUMMARY=1

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

rm -rf coverage
mkdir -p coverage

# The FendCore package does not resolve without its framework, which is built from Rust and not committed.
if [[ ! -d Vendor/FendCore/Frameworks/CFendCore.xcframework ]]; then
    say "Building Fend Core xcframework…"
    ./scripts/build-fend.sh
fi

say "Swift tests…"
swift test --enable-code-coverage
BIN=$(swift build --show-bin-path)
BUNDLE=$(find "$BIN" -maxdepth 1 -name '*.xctest' | head -1)
xcrun llvm-cov export -format=lcov \
    "$BUNDLE/Contents/MacOS/$(basename "$BUNDLE" .xctest)" \
    -instr-profile "$BIN/codecov/default.profdata" \
    -ignore-filename-regex='(\.build|Tests|Vendor)/' >coverage/swift.lcov
python3 scripts/lcov-to-sonar.py

say "Runtime tests…"
# No package in runtime/ needs an install script, so none are allowed to run.
(cd runtime && bun install --ignore-scripts --frozen-lockfile >/dev/null)
bun --config=runtime/bunfig.toml test ./runtime \
    --coverage --coverage-reporter=lcov --coverage-dir=coverage/runtime

if [[ "$SUMMARY" -eq 1 ]]; then
    say "Line coverage of the measured files"
    python3 - <<'PY'
import re

excluded = []
with open("sonar-project.properties", encoding="utf-8") as properties:
    text = properties.read().replace("\\\n", "")
match = re.search(r"^sonar\.coverage\.exclusions=(.*)$", text, re.M)
if match:
    for pattern in match.group(1).split(","):
        pattern = re.escape(pattern.strip()).replace(r"\*\*/", "(.*/)?").replace(r"\*\*", ".*").replace(r"\*", "[^/]*")
        excluded.append(re.compile("^" + pattern + "$"))

total = hit = 0
for report in ("coverage/swift.lcov", "coverage/runtime/lcov.info"):
    path, lines = None, {}
    def flush():
        global total, hit
        if path and not any(rule.match(path) for rule in excluded):
            covered = sum(lines.values())
            total += len(lines); hit += covered
            print(f"  {path:44} {covered:4}/{len(lines):<4} {100 * covered / max(len(lines), 1):5.1f}%")
    import os
    root = os.getcwd() + os.sep
    with open(report, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith("SF:"):
                flush()
                path, lines = line[3:].replace(root, ""), {}
            elif line.startswith("DA:"):
                number, hits = line[3:].split(",")[:2]
                lines[number] = lines.get(number, False) or int(hits) > 0
    flush()
print(f"  {'TOTAL':44} {hit:4}/{total:<4} {100 * hit / max(total, 1):5.1f}%")
PY
fi
