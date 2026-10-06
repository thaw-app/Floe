#!/usr/bin/env python3
"""Writes the fixture the calculator's replay harness reads: fend's own test cases.

fend keeps its inputs and expected answers in core/tests/integration_tests.rs. This copies the calls
that pair an input with an answer, test_eval and test_eval_simple, as they are written there, for the
version Cargo.lock pins. Run it again after changing that version:

    ./scripts/fend-corpus.py

Every path is fixed and relative to the repository. The one thing it reads from elsewhere is that file,
from fend's repository on GitHub at the pinned tag.
"""

import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CARGO_PINS = ROOT / "Vendor" / "FendCore" / "rust" / "Cargo.lock"
FIXTURE = ROOT / "Tests" / "FloeTests" / "Fixtures" / "FendIntegrationCorpus.swift"
SOURCE = "https://raw.githubusercontent.com/printfn/fend/v{version}/core/tests/integration_tests.rs"

LITERAL = r'"(?:[^"\\]|\\.)*"'
CALL = re.compile(rf"\b(?:test_eval|test_eval_simple)\(\s*{LITERAL}\s*,\s*{LITERAL}\s*,?\s*\)", re.S)

HEADER = '''//
//  FendIntegrationCorpus.swift
//  Project: Floe
//
//  Copyright (c) 2020-2025 the fend authors
//  Licensed under the MIT License, in LICENSES/fend-MIT
//
//  Written by scripts/fend-corpus.py. Do not edit: run the script again.

/// Verbatim calls from fend {version}'s core/tests/integration_tests.rs, each an input and the answer expected for it.
/// Kept to test_eval and test_eval_simple, which the harness reads the same way; expect_error is left out.
enum FendIntegrationCorpus {{
    static let version = "{version}"

    static let text = ##"""
{calls}
    """##
}}
'''


def pinned_version() -> str:
    lock = CARGO_PINS.read_text(encoding="utf-8")
    match = re.search(r'^name = "fend-core"\nversion = "([^"]+)"', lock, re.M)
    if match is None:
        sys.exit(f"error: no fend-core version in {CARGO_PINS}")
    return match.group(1)


def main() -> int:
    version = pinned_version()
    with urllib.request.urlopen(SOURCE.format(version=version), timeout=30) as response:
        source = response.read().decode("utf-8")
    calls = CALL.findall(source)
    if not calls or '"""##' in source:
        sys.exit("error: no calls found, or the source holds the fixture's own delimiter")
    # Indented as the literal is, so Swift takes the indentation back off every line.
    body = "\n".join("    " + line if line else "" for call in calls for line in call.split("\n"))
    FIXTURE.write_text(HEADER.format(version=version, calls=body), encoding="utf-8")
    print(f"wrote {FIXTURE.relative_to(ROOT)}: {len(calls)} calls from fend {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
