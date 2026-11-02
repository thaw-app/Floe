//
//  FileSearchModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing
import ThawUI

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
        #expect(try model.handleKey(key(FloeKeys.code(typing: "c"), [.command, .shift]), [.command, .shift]), "Command-Shift-C")
        #expect(try model.handleKey(key(FloeKeys.code(typing: "y"), .command), .command), "Command-Y")
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
        model.run(.showInFinder)
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

    /// The user's choices for files, with rows that record what they ran instead of acting on the Mac.
    private func choices(_ kind: KindActions, ran: @escaping (String) -> Void) -> AlternativeActions {
        let actions = AlternativeActions()
        actions.kindOf = { _ in .file }
        actions.host = AlternativeActions.Host(
            choices: { [SubjectKind.file.rawValue: kind] },
            floeActions: { _ in [ItemAction(title: "Copy Path", symbol: "doc.on.doc", id: .copyPath) { ran("copy path") }] },
            floeTitle: { _ in "Open" },
            openAsFloeDoes: { _ in ran("floe") }
        )
        return actions
    }

    @Test func returnOnAFileDoesWhatTheUserChoseForFiles() {
        var ran: [String] = []
        var copyPath = KindActions()
        copyPath.defaults = [.copyPath]
        let model = FileSearchModel()
        defer { model.cancel() }
        model.alternatives = choices(copyPath) { ran.append($0) }
        model.spotlight.opener = { _ in ran.append("opened") }
        let file = FileResult(url: URL(fileURLWithPath: "/floe-tests-no-such-folder/a.txt"), name: "a.txt", displayPath: "/floe-tests-no-such-folder", contentType: nil, lastUsed: nil)

        model.activate(file, flags: [])
        #expect(ran == ["copy path"])
        model.activate(file, flags: .option)
        #expect(ran == ["copy path", "opened"], "Return with keys held is Floe's, as in the root search")
        model.alternatives = choices(KindActions()) { ran.append($0) }
        model.activate(file, flags: [])
        #expect(ran == ["copy path", "opened", "opened"], "with nothing chosen the file opens")
    }

    @Test func theActionsMenuOfAFileFollowsTheUsersChoices() {
        var choice = KindActions()
        choice.defaults = [.copyPath]
        choice.hidden = [.quickLook]
        let model = FileSearchModel()
        defer { model.cancel() }
        model.alternatives = choices(choice) { _ in }
        let file = FileResult(url: URL(fileURLWithPath: "/floe-tests-no-such-folder/a.txt"), name: "a.txt", displayPath: "/floe-tests-no-such-folder", contentType: nil, lastUsed: nil)

        let rows = model.actions(for: file)
        #expect(rows.first??.title == "Copy Path", "the chosen row is what Return does")
        #expect(rows.contains { $0?.title == "Open" && $0?.id == .own }, "what Floe does stays in the menu")
        #expect(!rows.contains { $0?.id == .quickLook })
        #expect(!rows.contains { $0?.id == .copyPath }, "the default is the Return row, not listed twice")
    }

    @Test func aFilesKeysAreTheUsersOverFloesAndARowLeftOutOfTheMenuKeepsThem() {
        let commandO = KeyCombination(key: .o, modifiers: .command)
        var choice = KindActions()
        choice.shortcuts = [.copyName: commandO]
        choice.clearedKeys = [.quickLook]
        choice.hidden = [.copyPath]
        let model = FileSearchModel()
        defer { model.cancel() }
        model.alternatives = choices(choice) { _ in }
        let file = FileResult(url: URL(fileURLWithPath: "/floe-tests-no-such-folder/a.txt"), name: "a.txt", displayPath: "/floe-tests-no-such-folder", contentType: nil, lastUsed: nil)

        let keys = model.rowKeys(for: file)
        #expect(keys.key(for: .copyName) == commandO)
        #expect(keys.key(for: .quickLook) == nil, "the user took Floe's ⌘Y off Quick Look")
        #expect(keys.key(for: .copyPath) == FloeKeys.commandShiftC, "a row left out of the menu keeps its keys")
        let rows = model.actions(for: file).compactMap(\.self)
        #expect(rows.first { $0.id == .copyName }?.shortcut == commandO, "the menu shows the user's keys")
        #expect(!rows.contains { $0.id == .copyPath })
        #expect(model.rowKeys(for: nil) == keys, "with no file selected, the keys are still the user's for files")
    }

    @Test func theLauncherHandsTheFileSearchItsChoices() {
        let launcher = LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [], commands: []))
        #expect(launcher.fileSearch.alternatives === launcher.features.actions)
    }
}
