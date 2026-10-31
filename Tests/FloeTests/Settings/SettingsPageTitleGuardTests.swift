//
//  SettingsPageTitleGuardTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Testing

@Suite("Settings pages are named by the toolbar")
nonisolated struct SettingsPageTitleGuardTests {
    @Test("No page draws the header on its own, and the header has no title")
    func noPageTitle() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appending(path: "Sources/Floe")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("SettingsPageHeader()") || text.contains("heading.title") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty)
    }

    @Test("The window's toolbar names the page")
    func toolbarNamesThePage() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let settings = root.appending(path: "Sources/Floe/Settings")
        let view = try String(contentsOf: settings.appending(path: "SettingsView.swift"), encoding: .utf8)
        let window = try String(contentsOf: settings.appending(path: "SettingsWindow.swift"), encoding: .utf8)
        #expect(view.contains("ThawSettingsShell(title: Text(title))"))
        #expect(window.contains("sceneBridgingOptions = [.title, .toolbars]"))
        #expect(window.contains("toolbarStyle = .unified"))
    }
}
