//
//  ItemActionPanelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing
import ThawUI

/// Floe's own Actions menu, open in the panel: its rows, its search and submenus, and the keys that reach it.
@MainActor
struct ItemActionPanelTests {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ characters: String = "") throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
    }

    private func titles(_ panel: ItemActionPanel) -> [String] {
        panel.panelEntries.map(\.title)
    }

    @Test func aSeparatorPartsTheRowAfterItAndASubmenuIsMarked() {
        let panel = ItemActionPanel(rows: [
            nil,
            ItemAction(title: "Open With", symbol: "arrow.up.forward.app", children: [ItemAction(title: "Preview", symbol: "app")]),
            nil,
            nil,
            ItemAction(title: "Copy Path", symbol: "doc.on.doc", shortcut: KeyCombination(key: .c, modifiers: [.command, .shift])),
        ]) {}
        let entries = panel.panelEntries
        #expect(entries.map(\.title) == ["Open With", "Copy Path"])
        #expect(entries.map(\.startsGroup) == [false, true], "one line between groups, and none above the first row")
        #expect(entries.map(\.isSubmenu) == [true, false])
        guard case let .combination(keys) = entries[1].keys else {
            Issue.record("Copy Path's keys are drawn beside it")
            return
        }
        #expect(keys == KeyCombination(key: .c, modifiers: [.command, .shift]))
    }

    @Test func returnOpensASubmenuAndEscStepsBackThenCloses() throws {
        var closed = 0
        var opened: [String] = []
        let panel = ItemActionPanel(rows: [
            ItemAction(title: "Open With", symbol: "arrow.up.forward.app", children: [
                ItemAction(title: "Preview", symbol: "app") { opened.append("Preview") },
                ItemAction(title: "TextEdit", symbol: "app") { opened.append("TextEdit") },
            ]),
        ]) { closed += 1 }

        #expect(try panel.handleActionPanelKey(key(36), []))
        #expect(panel.panelSubmenuTitle == "Open With")
        #expect(titles(panel) == ["Preview", "TextEdit"])
        #expect(try panel.handleActionPanelKey(key(53), []))
        #expect(panel.panelSubmenuTitle == nil && closed == 0, "Esc leaves the submenu first")
        #expect(try panel.handleActionPanelKey(key(124), []), "→ opens it too")
        #expect(try panel.handleActionPanelKey(key(125), []))
        #expect(try panel.handleActionPanelKey(key(36), []))
        #expect(opened == ["TextEdit"] && closed == 1, "a row runs, and the panel closes")
    }

    @Test func typingSearchesEveryRowSubmenusIncluded() throws {
        let panel = ItemActionPanel(rows: [
            ItemAction(title: "Open With", symbol: "arrow.up.forward.app", children: [ItemAction(title: "Preview", symbol: "app")]),
            nil,
            ItemAction(title: "Copy Path", symbol: "doc.on.doc"),
            ItemAction(title: "Quick Look", symbol: "eye"),
        ]) {}
        #expect(try panel.handleActionPanelKey(key(35, [], "p"), []))
        #expect(try panel.handleActionPanelKey(key(15, .shift, "R"), [.shift]), "Shift types a capital")
        #expect(panel.panelQuery == "pR")
        #expect(titles(panel) == ["Preview"])
        #expect(panel.panelEntries.allSatisfy { !$0.startsGroup }, "a search lists its matches with no separators")
        #expect(try panel.handleActionPanelKey(key(51), []))
        #expect(titles(panel) == ["Open With", "Preview", "Copy Path"], "Delete takes the last letter off")
        #expect(try !panel.handleActionPanelKey(key(8, .command, "c"), [.command]), "⌘ keys are not typed into it")
        #expect(try panel.handleActionPanelKey(key(53), []))
        #expect(panel.panelQuery.isEmpty, "Esc clears the search before anything else")
    }

    @Test func theHostOpensAndClosesThePanel() {
        let host = ActionPanelHost()
        host.toggle([nil])
        #expect(host.panel == nil, "with no rows there is nothing to open")
        host.toggle([ItemAction(title: "Copy Path", symbol: "doc.on.doc")])
        #expect(host.panel != nil)
        host.panel?.closePanel()
        #expect(host.panel == nil, "a row run, or Esc at the top, closes it")
        host.toggle([ItemAction(title: "Copy Path", symbol: "doc.on.doc")])
        host.toggle([ItemAction(title: "Copy Path", symbol: "doc.on.doc")])
        #expect(host.panel == nil, "⌘K again closes it")
    }

    // MARK: - In the launcher

    private let app = AppEntry(name: "Floe Panel Test App", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))

    /// The app, found by its name and selected in the full panel, with its Actions menu open.
    private func openPanel() throws -> LauncherModel {
        let settings = AppSettings(defaults: MemoryDefaults())
        let model = LauncherModel(settings: settings, usage: UsageStore(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [app], commands: []))
        model.settings.launcherLayout = .extended
        model.query = app.name
        model.refresh()
        try #require(model.results.first?.item.id == RootItem.app(app).id)
        model.selection = 0
        model.actionPanel.toggle(model.rootActions(for: .app(app)))
        try #require(model.actionPanel.panel != nil)
        return model
    }

    @Test func typingWhileThePanelIsOpenSearchesItNotTheResults() throws {
        let model = try openPanel()
        #expect(try model.handlePanelKey(key(8, [], "c"), layout: .extended))
        #expect(model.actionPanel.panel?.panelQuery == "c")
        #expect(model.query == app.name, "the search on screen is left as it was")
        #expect(try model.handlePanelKey(key(40, .command, "k"), layout: .extended))
        #expect(model.actionPanel.panel == nil, "⌘K closes it")
    }

    @Test func aRowsKeysCloseThePanelAndRunTheRow() throws {
        let model = try openPanel()
        #expect(try model.handlePanelKey(key(FloeKeys.code(typing: "f"), [.command, .shift], "f"), layout: .extended))
        #expect(model.actionPanel.panel == nil)
        #expect(model.settings.favorites == [RootItem.app(app).id], "⌘⇧F ran Favorites, as with the panel closed")
    }

    @Test func returnRunsTheSelectedRowAndClosingTheLauncherClosesThePanel() throws {
        let model = try openPanel()
        let rows = try #require(model.actionPanel.panel).panelEntries
        let favorite = try #require(rows.firstIndex { $0.title == "Add to Favorites" })
        model.actionPanel.panel?.panelSelection = favorite
        #expect(try model.handlePanelKey(key(36), layout: .extended))
        #expect(model.settings.favorites == [RootItem.app(app).id])
        #expect(model.actionPanel.panel == nil)

        model.actionPanel.toggle(model.rootActions(for: .app(app)))
        model.panelDidHide()
        #expect(model.actionPanel.panel == nil, "closing the launcher closes its Actions menu")
    }
}
