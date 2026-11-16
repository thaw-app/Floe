//
//  KeyRoutingTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// The view the panel draws is the one that takes the keys, whatever was open when a command started.
@MainActor
struct KeyRoutingTests {
    /// What a session sent to its extension.
    private final class Recorder {
        var sent: [[String: Any]] = []
    }

    /// A mode that can be open when a command starts from outside the panel.
    enum Mode: CaseIterable {
        case menuBarSearch, menuItemSearch, clipboardHistory, fileSearch, noteDesk
    }

    private let model = LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [], commands: []))
    private let recorder = Recorder()

    private func open(_ mode: Mode) {
        switch mode {
        case .menuBarSearch: model.isSearchingMenuBar = true
        // No front app and no Accessibility, so nothing outside the test is read.
        case .menuItemSearch: model.menuItemSearch = MenuItemSearchModel(environment: .init(frontApp: { nil }, isTrusted: { false }))
        case .clipboardHistory: model.isShowingClipboardHistory = true
        case .fileSearch: model.isSearchingFiles = true
        case .noteDesk: model.noteDesk = NoteDeskModel(place: .elsewhere("Notes"), store: FolderNoteStore(folder: nil))
        }
    }

    private func isOpen(_ mode: Mode) -> Bool {
        switch mode {
        case .menuBarSearch: model.isSearchingMenuBar
        case .menuItemSearch: model.menuItemSearch != nil
        case .clipboardHistory: model.isShowingClipboardHistory
        case .fileSearch: model.isSearchingFiles
        case .noteDesk: model.noteDesk != nil
        }
    }

    /// Starts a command as a hotkey or a link does, without an extension process.
    private func start(_ command: ExtensionCommand = Fixture.command("hello")) throws -> ExtensionSession {
        model.runner.startsHost = { _ in }
        model.runner.run(command)
        let session = try #require(model.runner.session)
        session.transport = { [recorder] in recorder.sent.append($0) }
        return session
    }

    private func key(_ code: UInt16, _ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
    }

    private func escape() throws -> NSEvent {
        try key(53, "\u{1b}")
    }

    private func returnKey() throws -> NSEvent {
        try key(36, "\r")
    }

    private func isCommand(_ screen: OnScreen) -> Bool {
        if case .command = screen { true } else { false }
    }

    private func isSetup(_ screen: OnScreen) -> Bool {
        if case .setup = screen { true } else { false }
    }

    private func isClipboardHistory(_ screen: OnScreen) -> Bool {
        if case .clipboardHistory = screen { true } else { false }
    }

    private func isRootSearch(_ screen: OnScreen) -> Bool {
        if case .rootSearch = screen { true } else { false }
    }

    private func isAskAI(_ screen: OnScreen) -> Bool {
        if case .askAI = screen { true } else { false }
    }

    @Test(arguments: Mode.allCases)
    func aCommandStartedOverAModeTakesTheKeys(_ mode: Mode) throws {
        open(mode)
        _ = try start()
        #expect(isCommand(model.onScreen))
        #expect(model.handleKey(try escape()))
        #expect(recorder.sent.count == 1)
        #expect(recorder.sent.first?["type"] as? String == "pop")
        #expect(isOpen(mode), "the mode waits underneath until the command ends")
    }

    @Test func anAlertTakesReturnOverAMenuBarSearchBehindIt() throws {
        model.isSearchingMenuBar = true
        let session = try start()
        session.alert = AlertState(id: 7, title: "Delete?", message: nil, primaryTitle: "Delete", isDestructive: true, dismissTitle: "Cancel")
        #expect(model.handleKey(try returnKey()))
        #expect(recorder.sent.count == 1)
        #expect(recorder.sent.first?["type"] as? String == "reply")
        #expect(recorder.sent.first?["id"] as? Int == 7)
        #expect(recorder.sent.first?["result"] as? Bool == true)
        #expect(session.alert == nil)
    }

    @Test func aSetupFormIsInFrontOfARunningCommand() throws {
        _ = try start()
        model.isShowingClipboardHistory = true
        model.setup = SetupRequest(command: Fixture.command("hello"), kind: .arguments, fields: [])
        #expect(isSetup(model.onScreen))
        #expect(model.handleKey(try escape()))
        #expect(model.setup == nil)
        #expect(recorder.sent.isEmpty)
    }

    @Test func aCommandWithNoViewLeavesTheKeysWhereTheyWere() throws {
        model.isShowingClipboardHistory = true
        _ = try start(Fixture.command("tick", mode: "no-view"))
        #expect(isClipboardHistory(model.onScreen))
    }

    @Test func withNothingOpenTheRootSearchIsOnScreen() {
        #expect(isRootSearch(model.onScreen))
        model.askAI = AskAIModel(question: "q", source: nil, request: { _, _ in "" })
        #expect(isAskAI(model.onScreen))
    }
}
