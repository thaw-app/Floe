//
//  ThemeRootsGuardTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Testing

/// AppKit hosting gives a window a new SwiftUI environment, so a root without the theme silently draws Thaw's look.
/// It reads every source file, so it stays off the main actor, where every main actor test in the run would wait for it.
@Suite("Floe's windows take Floe's theme")
nonisolated struct ThemeRootsGuardTests {
    @Test("Every hosting root in the app sets the theme")
    func everyRootSetsTheTheme() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = try #require(FileManager.default.enumerator(at: root.appending(path: "Sources/Floe"), includingPropertiesForKeys: nil))
        let hosting = try Regex(#"NSHosting\w+\(rootView:"#)
        var hostingRoots = 0
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let roots = text.matches(of: hosting).count
            hostingRoots += roots
            if text.ranges(of: ".thawTheme(.floe)").count < roots {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(hostingRoots > 0, "The scan found no hosting views, so it no longer guards anything.")
        #expect(offenders.isEmpty, "Add .thawTheme(.floe) to the root view in: \(offenders.joined(separator: ", "))")
    }
}
