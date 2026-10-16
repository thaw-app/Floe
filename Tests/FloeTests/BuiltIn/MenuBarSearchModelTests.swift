//
//  MenuBarSearchModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices
@testable import Floe
import Testing

@MainActor
struct MenuBarSearchModelTests {
    private let scratch = MemoryDefaults()
    private let settings: AppSettings

    init() {
        settings = AppSettings(defaults: scratch)
    }

    private func extra(_ name: String, owner: String = "Control Center") -> MenuBarExtra {
        MenuBarExtra(id: "\(owner)|\(name)", name: name, ownerName: owner, ownerURL: nil, frame: .zero, element: AXUIElementCreateSystemWide())
    }

    /// A model that already holds a scan's items, as it does once the menu bar was read.
    private func makeModel(_ names: [String] = ["Wi-Fi", "Battery", "Clock"]) -> MenuBarSearchModel {
        let model = MenuBarSearchModel(settings: settings, recents: MenuBarSearchRecents(defaults: scratch))
        model.extras = names.map { extra($0) }
        model.refresh()
        return model
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func withoutAQueryTheRecentItemsComeFirstThenTheRestInMenuBarOrder() {
        let model = makeModel()
        #expect(model.results.map(\.extra.name) == ["Wi-Fi", "Battery", "Clock"])
        #expect(model.results.map(\.section) == ["Menu Bar", "Menu Bar", "Menu Bar"])

        model.recents.record("Control Center|Clock")
        model.refresh()
        #expect(model.results.map(\.extra.name) == ["Clock", "Wi-Fi", "Battery"])
        #expect(model.results.map(\.section) == ["Recent", "Menu Bar", "Menu Bar"])
    }

    @Test func aQueryKeepsTheMatchingItemsAndPutsTheSelectionBackOnTheFirst() {
        let model = makeModel()
        model.selection = 2
        model.query = "bat"
        #expect(model.results.map(\.extra.name) == ["Battery"])
        #expect(model.results.first?.section == nil, "matches have no section title")
        #expect(model.selection == 0)
        #expect(model.selectedExtra?.name == "Battery")
    }

    @Test func theArrowsMoveTheSelectionAndStopAtTheEnds() throws {
        let model = makeModel()
        #expect(try model.handleKey(key(126), []))
        #expect(model.selection == 0)
        for _ in 0 ..< 5 {
            #expect(try model.handleKey(key(125), []))
        }
        #expect(model.selection == 2)
        #expect(try !model.handleKey(key(0), []), "a letter goes on to the search field")
    }

    @Test func escapeClearsAQueryFirstAndOnlyThenLeavesTheSearch() throws {
        let model = makeModel()
        var closed = 0
        model.host.close = { closed += 1 }
        model.query = "bat"
        #expect(try model.handleKey(key(53), []))
        #expect(model.query.isEmpty)
        #expect(closed == 0)
        #expect(try model.handleKey(key(53), []))
        #expect(closed == 1)
    }

    @Test func commandKAsksTheHostForTheActionsMenu() throws {
        let model = makeModel()
        var shown = 0
        model.host.showActions = { shown += 1 }
        #expect(try model.handleKey(key(40, .command), .command))
        #expect(shown == 1)
    }

    @Test func renamingAnItemStoresTheNameAndKeepsTheSelectionWhereItWas() throws {
        let model = makeModel()
        var refocused = 0
        model.host.refocus = { refocused += 1 }
        model.selection = 1
        #expect(try model.handleKey(key(14, .command), .command), "Command-E")
        #expect(model.renamingItem == "Control Center|Battery")
        #expect(model.renameDraft == "Battery")
        #expect(try !model.handleKey(key(125), []), "while renaming, the arrows belong to the name field")

        model.renameDraft = "  Power  "
        #expect(try model.handleKey(key(36), []))
        #expect(model.renamingItem == nil)
        #expect(settings.menuBarItemNames == ["Control Center|Battery": "Power"])
        #expect(model.selection == 1)
        #expect(model.selectedExtra.map(model.displayName) == "Power")
        #expect(refocused == 1)
    }

    @Test func anEmptyNameGoesBackToTheOneTheAppReportsAndEscapeLeavesTheNameAlone() throws {
        settings.menuBarItemNames = ["Control Center|Wi-Fi": "Network"]
        let model = makeModel()
        model.beginRenamingSelection()
        model.renameDraft = "Something else"
        #expect(try model.handleKey(key(53), []))
        #expect(model.renamingItem == nil)
        #expect(settings.menuBarItemNames == ["Control Center|Wi-Fi": "Network"])

        model.beginRenamingSelection()
        model.renameDraft = " "
        model.commitRename()
        #expect(settings.menuBarItemNames.isEmpty)
    }

    @Test func anItemsActionsOfferRestoringItsNameOnlyOnceItWasRenamed() {
        let model = makeModel()
        let item = extra("Wi-Fi")
        #expect(model.actions(for: item).compactMap { $0?.title } == ["Click Item", "Edit Name", "Copy Name"])
        settings.menuBarItemNames[item.id] = "Network"
        #expect(model.actions(for: item).compactMap { $0?.title } == ["Click Item", "Edit Name", "Copy Name", "Restore Original Name"])
    }

    @Test func theLauncherShowsTheSearchAndEscapeInItGoesBackToTheRoot() throws {
        let launcher = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        var changes = 0
        let subscription = launcher.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        launcher.isSearchingMenuBar = true
        let before = changes
        launcher.menuBarSearch.query = "bat"
        launcher.menuBarSearch.selection = 0
        #expect(changes == before, "typing in the menu bar search does not republish the launcher model")

        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.menuBarSearch.query.isEmpty)
        #expect(launcher.isSearchingMenuBar)
        #expect(try launcher.handleKey(key(53)))
        #expect(!launcher.isSearchingMenuBar)
    }

    @Test func askingForAccessGoesToWhatKeepsCheckingForTheAnswer() {
        let scratch = MemoryDefaults()
        var asked = 0
        let model = MenuBarSearchModel(settings: AppSettings(defaults: scratch), askForAccess: { asked += 1 })

        model.requestAccess()

        #expect(asked == 1, "one request, and no single timed check after it")
    }
}
