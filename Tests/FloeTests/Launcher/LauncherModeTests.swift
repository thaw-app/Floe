//
//  LauncherModeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine
@testable import Floe
import Testing

/// A mode opened over another leaves it underneath, and leaving the one on screen shows the one under it.
@MainActor
struct LauncherModeTests {
    private func desk() -> NoteDeskModel {
        NoteDeskModel(place: .elsewhere("Notes"), store: FolderNoteStore(folder: nil))
    }

    private func asking() -> AskAIModel {
        AskAIModel(question: "q", source: nil, request: { _, _ in "" })
    }

    private func kinds(_ stack: ModeStack) -> [LauncherMode.Kind] {
        stack.modes.map(\.kind)
    }

    @Test func aModeEnteredOverAnotherLeavesItUnderneath() {
        var stack = ModeStack()
        let underneath = stack.enter(.fileSearch)
        let over = stack.enter(.clipboardHistory)
        #expect(underneath == nil && over == nil)
        #expect(stack.top?.kind == .clipboardHistory)
        let left = stack.leave(.clipboardHistory)
        #expect(left?.kind == .clipboardHistory)
        #expect(stack.top?.kind == .fileSearch)
    }

    @Test func aKindAlreadyOpenComesToTheTopAndItsEarlierShowingIsHandedBack() throws {
        var stack = ModeStack()
        let first = desk()
        let second = desk()
        _ = stack.enter(.noteDesk(first))
        _ = stack.enter(.fileSearch)
        let handed = stack.enter(.noteDesk(second))
        let replaced = try #require(handed)
        guard case let .noteDesk(handedBack) = replaced else {
            Issue.record("the earlier desk is handed back")
            return
        }
        #expect(handedBack === first)
        #expect(kinds(stack) == [.fileSearch, .noteDesk])
    }

    @Test func enteringTheModeOnScreenAgainIsNoNewShowing() {
        var stack = ModeStack()
        _ = stack.enter(.fileSearch)
        let again = stack.enter(.fileSearch)
        #expect(again == nil)
        #expect(kinds(stack) == [.fileSearch])
    }

    @Test func leavingAModeUnderneathKeepsTheOneOnScreen() {
        var stack = ModeStack()
        _ = stack.enter(.fileSearch)
        _ = stack.enter(.menuBarSearch)
        _ = stack.leave(.fileSearch)
        #expect(kinds(stack) == [.menuBarSearch])
        let absent = stack.leave(.askAI)
        #expect(absent == nil)
    }

    @Test func leavingAllHandsBackTheModeOnScreenFirst() {
        var stack = ModeStack()
        _ = stack.enter(.fileSearch)
        _ = stack.enter(.clipboardHistory)
        let all = stack.leaveAll()
        #expect(all.map(\.kind) == [.clipboardHistory, .fileSearch])
        #expect(stack.top == nil)
    }

    @Test func anAskAIConversationIsHeldWhileItIsOpenAnywhere() {
        var stack = ModeStack()
        let conversation = asking()
        _ = stack.enter(.askAI(conversation))
        _ = stack.enter(.fileSearch)
        #expect(stack.holds(conversation))
        #expect(!stack.holds(asking()))
        _ = stack.leave(.askAI)
        #expect(!stack.holds(conversation))
    }

    private let model = LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])

    private func escape() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
    }

    @Test func escapeInAModeOpenedOverTheFileSearchShowsTheFileSearchAgain() throws {
        model.openFileSearch(with: "invoice")
        model.enter(.clipboardHistory)
        #expect(model.mode?.kind == .clipboardHistory)
        #expect(model.handleKey(try escape()))
        #expect(model.isSearchingFiles)
        #expect(model.fileSearch.query == "invoice", "the file search comes back as it was left")
    }

    @Test func theFileSearchShortcutOpensOverTheViewOnScreenAndEscGoesBackToIt() throws {
        model.enter(.clipboardHistory)
        model.runFromHotkey(.fileSearch)
        #expect(model.isSearchingFiles)
        #expect(model.handleKey(try escape()))
        #expect(model.mode?.kind == .clipboardHistory)
    }

    @Test func theNotesShortcutOpensOverTheViewOnScreen() {
        // A desk with no store of its own, so no other app is asked for notes.
        model.settings.notesApp = .antinote
        model.enter(.clipboardHistory)
        model.runFromHotkey(.noteDesk)
        #expect(model.noteDesk != nil)
        model.closeNoteDesk()
        #expect(model.mode?.kind == .clipboardHistory)
    }

    @Test func aMenuSearchUnderAnotherModeReadsTheMenusOnceAccessIsGranted() {
        var trusted = false
        model.menuItemEnvironment = MenuItemSearchModel.Environment(
            frontApp: { nil }, isTrusted: { trusted }, askForAccess: {}, scan: { _ in [] }, choose: { _, _ in }
        )
        model.openMenuItemSearch()
        let search = model.menuItemSearch
        model.enter(.clipboardHistory)
        trusted = true
        model.accessibilityWasGranted()
        #expect(search?.accessGranted == true, "it shows the menus, not the request for access, when it is back")
    }

    @Test func theModeEnteredLastIsOnScreenWhicheverItIs() {
        model.enter(.menuBarSearch)
        model.openFileSearch(with: "")
        #expect(model.isSearchingFiles, "the file search is drawn over the menu bar search, not hidden under it")
        model.closeFileSearch()
        #expect(model.mode?.kind == .menuBarSearch)
    }

    @Test func anAnswerCoveredByAnotherModeWaitsAndComesBack() {
        model.askAIRequest = { _, _ in "" }
        model.openAskAI("how do tides work")
        let conversation = model.askAI
        model.openFileSearch(with: "")
        // What the answer view does as it goes off screen.
        if let conversation {
            model.leaveAskAI(conversation)
        }
        #expect(conversation?.state != .cancelled)
        model.closeFileSearch()
        #expect(model.askAI === conversation)
    }

    @Test func anAnswerNoLongerOpenStopsAsItsViewGoes() {
        model.askAIRequest = { _, _ in "" }
        model.openAskAI("how do tides work")
        let conversation = model.askAI
        model.closeAskAI()
        #expect(conversation?.state == .cancelled)
        #expect(model.askAI == nil)
    }

    @Test func resetEndsEveryModeAndSavesTheNotesUnderneath() {
        model.enter(.noteDesk(desk()))
        model.openFileSearch(with: "")
        model.noteDeskSave = nil
        model.reset()
        #expect(model.mode == nil)
        #expect(model.modes.modes.isEmpty)
        #expect(model.noteDeskSave != nil, "the desk under the file search is saved as it goes")
    }

    @Test func thePanelSizeFollowsTheModeOnScreen() {
        var sizes: [NSSize] = []
        let subscription = model.panelWindowSizes(settings: model.settings).sink { sizes.append($0) }
        defer { subscription.cancel() }
        let steps: [() -> Void] = [
            { model.openFileSearch(with: "") },
            { model.enter(.clipboardHistory) },
            { model.closeClipboardHistory() },
            { model.enter(.askAI(asking())) },
            { model.reset() },
        ]
        for step in steps {
            step()
            #expect(sizes.last == model.panelState.windowSize(in: model.settings.launcherLayout))
        }
    }
}
