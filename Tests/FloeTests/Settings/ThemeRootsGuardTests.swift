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
    private static let theme = ".thawTheme(.floe)"

    /// The roots in some source text that don't set the theme: in the initializer's own parentheses, or for a root named
    /// from a local, between that local's declaration and the initializer.
    private static func unthemedRoots(in text: String) throws -> [String] {
        let hosting = try Regex(#"NSHosting\w+\(\s*rootView:\s*"#)
        return text.matches(of: hosting).compactMap { match -> String? in
            let root = text[match.range.upperBound...]
            var depth = 1
            let end = root.firstIndex { character in
                depth += character == "(" ? 1 : character == ")" ? -1 : 0
                return depth == 0
            } ?? root.endIndex
            let argument = root[..<end]
            if argument.contains(theme) {
                return nil
            }
            let declaration = text[..<match.range.lowerBound].ranges(of: "let \(argument) = ").last
            if let declaration, text[declaration.lowerBound ..< match.range.lowerBound].contains(theme) {
                return nil
            }
            return String(argument)
        }
    }

    @Test("Every hosting root in the app sets the theme")
    func everyRootSetsTheTheme() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = try #require(FileManager.default.enumerator(at: root.appending(path: "Sources/Floe"), includingPropertiesForKeys: nil))
        var scanned = 0
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            scanned += text.ranges(of: "(rootView:").count
            offenders += try Self.unthemedRoots(in: text).map { "\(file.lastPathComponent): \($0)" }
        }
        #expect(scanned > 0, "The scan found no hosting views, so it no longer guards anything.")
        #expect(offenders.isEmpty, "Add \(Self.theme) to these roots: \(offenders.joined(separator: ", "))")
    }

    @Test("The scan checks each root on its own", arguments: [
        ("NSHostingView(rootView: Pane().thawTheme(.floe))", 0),
        ("NSHostingView(\n    rootView: Pane().thawTheme(.floe)\n)", 0),
        ("let view = Pane()\n    .thawTheme(.floe)\nwindow.contentView = NSHostingView(rootView: view)", 0),
        ("NSHostingView(rootView: Pane())", 1),
        ("NSHostingView(\n    rootView: Pane()\n)", 1),
        ("NSHostingController(rootView: Pane())", 1),
        ("NSHostingView(rootView: Pane().thawTheme(.floe))\nNSHostingView(rootView: Other())", 1),
        ("let view = Pane()\nNSHostingView(rootView: view)\nOther().thawTheme(.floe)", 1),
    ])
    func scan(source: String, unthemed: Int) throws {
        #expect(try Self.unthemedRoots(in: source).count == unthemed)
    }
}
