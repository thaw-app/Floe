#!/usr/bin/env python3
"""Generates Floe's credits from its dependencies.

Usage, from anywhere:
    scripts/generate-credits.py

Writes two files:
    CREDITS.md                  the list for the repository, with versions
    Sources/Floe/App/Credits.swift  the same list for the acknowledgements page that About opens

Adapted from Thaw's script of the same name, which builds CREDITS.md from a translators export.
Floe has no translations yet, so this one lists who builds the app and what it is built from. Versions are read
from the files that pin them, so run it again after changing a dependency:
    Package.resolved      Swift packages
    runtime/package.json  the extension runtime's packages
    Vendor/FendCore/rust/Cargo.lock  the Rust crates behind the calculator
Links come from FloeLinks in project.yml, the one place the app's web links are kept.

Every path is fixed and relative to the repository, so the script reads and writes nowhere else.
"""

import json
import re
import sys
from pathlib import Path
from typing import NamedTuple, Optional

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "project.yml"
SWIFT_PINS = ROOT / "Package.resolved"
RUNTIME_MANIFEST = ROOT / "runtime" / "package.json"
CARGO_PINS = ROOT / "Vendor" / "FendCore" / "rust" / "Cargo.lock"
MARKDOWN = ROOT / "CREDITS.md"
SWIFT = ROOT / "Sources" / "Floe" / "App" / "Credits.swift"


class Dependency(NamedTuple):
    name: str
    # The entry in project.yml's FloeLinks that holds the project's URL.
    link: str
    license: str
    # What Floe uses it for, as a sentence without the final period.
    use: str
    # Where the version comes from: "swift", "runtime", "cargo" or "" for none.
    source: str = ""
    # The Package.resolved identity, package.json name or crate name to look up.
    key: str = ""
    # Left out of the credits until its version can be found, for dependencies still being added.
    optional: bool = False
    # "origin" for a project Floe carries code from, which the page credits apart from the libraries.
    group: str = "library"


APACHE_2 = "Apache-2.0"

DEPENDENCIES = [
    Dependency("Thaw", "thaw", "GPL-3.0",
               "ThawUI, ThawConcurrency, the hotkey code, the HUD, the glass styles, the Privacy pane, the About and "
               "acknowledgements pages, the diagnostic logger, the release notes reader and the search panel design. "
               "Copyright © 2026 Toni Förster et al", group="origin"),
    # The license asks for this exact credit line wherever Floe lists what it is built from.
    Dependency("Droppy Code", "droppyCode", "AGPL-3.0",
               "Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app. Floe uses its login shell "
               "environment, its process runner, the tools and the streamed API request that answer AI.ask "
               "and Ask AI, its reading of the claude tool's streamed answer, the way it starts pi "
               "and hands opencode its configuration, "
               "its hang watchdog and the folder watcher behind hot reload, each modified for Floe and used with "
               "his permission", group="origin"),
    Dependency("CompactSlider", "compactSlider", "MIT", "Used by ThawUI", "swift", "compactslider"),
    Dependency("Sparkle", "sparkle", "MIT", "Checks for updates and installs them", "swift", "sparkle",
               optional=True),
    Dependency("swift-subprocess", "swiftSubprocess", APACHE_2, "Starts and stops the process an extension runs in",
               "swift", "swift-subprocess"),
    Dependency("swift-system", "swiftSystem", APACHE_2, "Used by swift-subprocess", "swift", "swift-system"),
    Dependency("swift-markdown", "swiftMarkdown", APACHE_2, "Reads the Markdown in detail views",
               "swift", "swift-markdown"),
    Dependency("swift-cmark", "swiftCmark", "BSD-2-Clause", "Used by swift-markdown", "swift", "swift-cmark"),
    Dependency("swift-argument-parser", "swiftArgumentParser", APACHE_2, "Reads the command line options",
               "swift", "swift-argument-parser"),
    Dependency("swift-algorithms", "swiftAlgorithms", APACHE_2, "Picks the best matches and drops repeats in lists",
               "swift", "swift-algorithms"),
    Dependency("swift-numerics", "swiftNumerics", APACHE_2, "Used by swift-algorithms", "swift", "swift-numerics"),
    Dependency("swift-async-algorithms", "swiftAsyncAlgorithms", APACHE_2,
               "Waits for typing and folder changes to settle", "swift", "swift-async-algorithms"),
    Dependency("swift-collections", "swiftCollections", APACHE_2, "Used by swift-async-algorithms",
               "swift", "swift-collections"),
    Dependency("fend", "fend", "MIT", "Calculates and converts units in the search", "cargo", "fend-core"),
    Dependency("Bun", "bun", "MIT", "Runs extensions"),
    Dependency("React", "react", "MIT", "Renders extensions", "runtime", "react"),
    Dependency("react-reconciler", "react", "MIT", "Turns what an extension renders into Floe's views",
               "runtime", "react-reconciler"),
    Dependency("Raycast extensions", "raycastExtensions", "each extension keeps its own license",
               "The API Floe implements"),
]


TRADEMARK = "Raycast is a trademark of Raycast Technologies Inc. Floe is not affiliated with Raycast."


def read_links() -> dict:
    """The name and URL of each entry under FloeLinks in project.yml."""
    links = {}
    inside = False
    for line in PROJECT.read_text(encoding="utf-8").splitlines():
        if line.strip() == "FloeLinks:":
            inside = True
            continue
        if not inside:
            continue
        match = re.fullmatch(r"\s+(\w+):\s+(https?://\S+)", line)
        if match is None:
            break
        links[match.group(1)] = match.group(2)
    return links


def swift_version(identity: str) -> Optional[str]:
    """The version, or short revision, Package.resolved pins a Swift package at."""
    if not SWIFT_PINS.is_file():
        return None
    pins = json.loads(SWIFT_PINS.read_text(encoding="utf-8")).get("pins", [])
    for pin in pins:
        if pin.get("identity") == identity:
            state = pin.get("state", {})
            return state.get("version") or state.get("revision", "")[:7] or None
    return None


def runtime_version(name: str) -> Optional[str]:
    """The version range runtime/package.json asks for."""
    manifest = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
    return manifest.get("dependencies", {}).get(name)


def cargo_version(crate: str) -> Optional[str]:
    """The version Cargo.lock pins a crate at."""
    lock = CARGO_PINS.read_text(encoding="utf-8")
    match = re.search(rf'^name = "{re.escape(crate)}"\nversion = "([^"]+)"', lock, re.M)
    return match.group(1) if match else None


VERSION_READERS = {"swift": swift_version, "runtime": runtime_version, "cargo": cargo_version}


def version_of(dependency: Dependency) -> Optional[str]:
    reader = VERSION_READERS.get(dependency.source)
    return reader(dependency.key) if reader else None


def listed(dependencies: list) -> list:
    """Each dependency with its version, without the optional ones that are not pinned yet."""
    pairs = [(dependency, version_of(dependency)) for dependency in dependencies]
    return [(dependency, version) for dependency, version in pairs if version or not dependency.optional]


def detail(dependency: Dependency) -> str:
    """The line under a name: what it is used for, then its license."""
    license_text = dependency.license
    separator = ". " if license_text[0].isupper() else "; "
    return f"{dependency.use}{separator}{license_text}."


def render_markdown(entries: list, links: dict) -> str:
    lines = [
        "# Credits",
        "",
        "Who translates Floe and what it is built from. This file is written by",
        "`scripts/generate-credits.py`; change the script and run it again instead of editing it.",
        "The people who contribute code and documentation are on the repository's",
        "[contributors page](https://github.com/thaw-app/Floe/graphs/contributors).",
        "",
        "## Translators",
        "",
        "Floe is translated by volunteers on [Crowdin](https://crowdin.com/project/floe). No language is",
        "finished yet; the people who translate it will be listed here. To help, or to ask for a",
        "language, join the project there.",
        "",
        "## Built from",
        "",
    ]
    for dependency, version in entries:
        url = links.get(dependency.link)
        name = f"[{dependency.name}]({url})" if url else dependency.name
        pinned = f" `{version}`" if version else ""
        lines.append(f"- {name}{pinned}: {detail(dependency)}")
    lines += ["", TRADEMARK, ""]
    return "\n".join(lines)


def swift_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


SWIFT_HEADER = """\
//
//  Credits.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Written by scripts/generate-credits.py. Change the script and run it again instead of editing this file.

import Foundation

/// One project Floe is built from, as the acknowledgements page lists it.
struct Credit: Identifiable {
    /// An origin is a project Floe carries code from; a library is one it links or runs.
    enum Group {
        case origin, library
    }

    let name: String
    let detail: String
    /// Names an entry in Info.plist's FloeLinks.
    let link: String
    let group: Group

    var id: String { name }
}

enum Credits {
    static let all: [Credit] = [
"""

SWIFT_FOOTER = """\
    ]

    static var origins: [Credit] {{
        all.filter {{ $0.group == .origin }}
    }}

    static var libraries: [Credit] {{
        all.filter {{ $0.group == .library }}
    }}

    static let trademark = {trademark}
}}
"""


def render_swift(entries: list) -> str:
    rows = [
        f"        Credit(name: {swift_string(dependency.name)}, detail: {swift_string(detail(dependency))}, "
        f"link: {swift_string(dependency.link)}, group: .{dependency.group}),\n"
        for dependency, _ in entries
    ]
    return SWIFT_HEADER + "".join(rows) + SWIFT_FOOTER.format(trademark=swift_string(TRADEMARK))


def warn_about_missing_links(entries: list, links: dict) -> None:
    for dependency, _ in entries:
        if dependency.link not in links:
            print(f"warning: project.yml's FloeLinks has no '{dependency.link}' entry, "
                  f"so {dependency.name} is listed without a link", file=sys.stderr)


def main() -> int:
    links = read_links()
    entries = listed(DEPENDENCIES)
    warn_about_missing_links(entries, links)
    MARKDOWN.write_text(render_markdown(entries, links), encoding="utf-8")
    SWIFT.write_text(render_swift(entries), encoding="utf-8")
    kept = [dependency for dependency, _ in entries]
    skipped = [dependency.name for dependency in DEPENDENCIES if dependency not in kept]
    note = f", left out until pinned: {', '.join(skipped)}" if skipped else ""
    print(f"wrote {MARKDOWN.name} and {SWIFT.relative_to(ROOT)}: {len(entries)} entries{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
