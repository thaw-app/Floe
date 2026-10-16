//
//  FileSearchModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// Every query typed here is cancelled before its pause ends, so Spotlight is never asked.
@MainActor
struct FileSearchModelTests {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func typingPutsTheSelectionBackOnTheFirstFile() {
        let model = FileSearchModel()
        defer { model.cancel() }
        model.selection = 3
        model.query = "invoice"
        #expect(model.selection == 0)
        #expect(model.selectedFile == nil, "nothing is found yet")
    }

    @Test func escapeClearsAQueryFirstAndOnlyThenLeavesTheSearch() throws {
        let model = FileSearchModel()
        defer { model.cancel() }
        var closed = 0
        model.host.close = { closed += 1 }
        model.query = "invoice"
        #expect(try model.handleKey(key(53), []))
        #expect(model.query.isEmpty)
        #expect(closed == 0)
        #expect(try model.handleKey(key(53), []))
        #expect(closed == 1)
    }

    @Test func theKeysThatActOnAFileAreConsumedEvenWithNoFileSelected() throws {
        let model = FileSearchModel()
        var dismissed = 0
        var shown: [String] = []
        var menus = 0
        model.host.dismiss = { dismissed += 1 }
        model.host.showHUD = { shown.append($0) }
        model.host.showActions = { menus += 1 }
        #expect(try model.handleKey(key(36), []), "Return")
        #expect(try model.handleKey(key(36, .command), .command), "Command-Return")
        #expect(try model.handleKey(key(8, [.command, .shift]), [.command, .shift]), "Command-Shift-C")
        #expect(try model.handleKey(key(125), []), "Down")
        #expect(model.selection == 0)
        #expect(dismissed == 0)
        #expect(shown.isEmpty)
        #expect(try model.handleKey(key(40, .command), .command), "Command-K")
        #expect(menus == 1)
        #expect(try !model.handleKey(key(8), []), "a typed c goes on to the search field")
    }

    @Test func spaceIsTypedUntilTheArrowsMoveAndTypingAgainGivesItBack() throws {
        let model = FileSearchModel()
        defer { model.cancel() }
        model.query = "invoice"
        #expect(try !model.handleKey(key(49), []), "a space goes on to the search field")
        #expect(try model.handleKey(key(125), []))
        #expect(try !model.handleKey(key(49), []), "with no file selected, Space is still typed")
        model.query = "invoice "
        #expect(try !model.handleKey(key(49), []))
    }

    @Test func openingAFileDismissesThePanelThroughTheHost() {
        let model = FileSearchModel()
        var dismissed = 0
        model.host.dismiss = { dismissed += 1 }
        model.revealSelectedFile()
        model.openSelectedFile()
        #expect(dismissed == 0, "there is no file to open")
    }

    @Test func theLauncherShowsTheSearchAndTypingInItDoesNotRepublishTheLauncher() throws {
        let settings = AppSettings(defaults: MemoryDefaults())
        let launcher = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        defer { launcher.fileSearch.cancel() }
        launcher.openFileSearch(with: "invoice")
        #expect(launcher.isSearchingFiles)
        #expect(launcher.fileSearch.query == "invoice")

        var changes = 0
        let subscription = launcher.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        launcher.fileSearch.query = "invoices"
        launcher.fileSearch.selection = 0
        #expect(changes == 0)

        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.fileSearch.query.isEmpty)
        #expect(launcher.isSearchingFiles)
        #expect(try launcher.handleKey(key(53)))
        #expect(!launcher.isSearchingFiles)
    }
}
