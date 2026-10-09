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

    var id: String {
        name
    }
}

enum Credits {
    static let all: [Credit] = [
        Credit(name: "Thaw", detail: "ThawUI, ThawConcurrency, the hotkey code, the HUD, the glass styles, the Privacy pane, the About and acknowledgements pages, the diagnostic logger, the release notes reader and the search panel design. Copyright © 2026 Toni Förster et al. GPL-3.0.", link: "thaw", group: .origin),
        Credit(name: "Droppy Code", detail: "Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app. Floe uses its login shell environment, its process runner, the tools and the streamed API request that answer AI.ask and Ask AI, its reading of the claude tool's streamed answer, the way it starts pi and hands opencode its configuration, its hang watchdog and the folder watcher behind hot reload, each modified for Floe and used with his permission. AGPL-3.0.", link: "droppyCode", group: .origin),
        Credit(name: "CompactSlider", detail: "Used by ThawUI. MIT.", link: "compactSlider", group: .library),
        Credit(name: "Sparkle", detail: "Checks for updates and installs them. MIT.", link: "sparkle", group: .library),
        Credit(name: "swift-subprocess", detail: "Starts and stops the process an extension runs in. Apache-2.0.", link: "swiftSubprocess", group: .library),
        Credit(name: "swift-system", detail: "Used by swift-subprocess. Apache-2.0.", link: "swiftSystem", group: .library),
        Credit(name: "swift-markdown", detail: "Reads the Markdown in detail views. Apache-2.0.", link: "swiftMarkdown", group: .library),
        Credit(name: "swift-cmark", detail: "Used by swift-markdown. BSD-2-Clause.", link: "swiftCmark", group: .library),
        Credit(name: "swift-argument-parser", detail: "Reads the command line options. Apache-2.0.", link: "swiftArgumentParser", group: .library),
        Credit(name: "swift-algorithms", detail: "Picks the best matches and drops repeats in lists. Apache-2.0.", link: "swiftAlgorithms", group: .library),
        Credit(name: "swift-numerics", detail: "Used by swift-algorithms. Apache-2.0.", link: "swiftNumerics", group: .library),
        Credit(name: "swift-async-algorithms", detail: "Waits for typing and folder changes to settle. Apache-2.0.", link: "swiftAsyncAlgorithms", group: .library),
        Credit(name: "swift-collections", detail: "Used by swift-async-algorithms. Apache-2.0.", link: "swiftCollections", group: .library),
        Credit(name: "fend", detail: "Calculates and converts units in the search. MIT.", link: "fend", group: .library),
        Credit(name: "nucleo", detail: "Matches file names in the fast file search. MPL-2.0.", link: "nucleo", group: .library),
        Credit(name: "ignore", detail: "Walks the home folder for the fast file search. MIT.", link: "ignore", group: .library),
        Credit(name: "Rayon", detail: "Matches file names on several cores at once. MIT.", link: "rayon", group: .library),
        Credit(name: "Bun", detail: "Runs extensions. MIT.", link: "bun", group: .library),
        Credit(name: "React", detail: "Renders extensions. MIT.", link: "react", group: .library),
        Credit(name: "react-reconciler", detail: "Turns what an extension renders into Floe's views. MIT.", link: "react", group: .library),
        Credit(name: "Raycast extensions", detail: "The API Floe implements; each extension keeps its own license.", link: "raycastExtensions", group: .library),
    ]

    static var origins: [Credit] {
        all.filter { $0.group == .origin }
    }

    static var libraries: [Credit] {
        all.filter { $0.group == .library }
    }

    static let trademark = "Raycast is a trademark of Raycast Technologies Inc. Floe is not affiliated with Raycast."
}
