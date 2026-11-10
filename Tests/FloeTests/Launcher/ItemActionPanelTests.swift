//
//  ItemActionPanelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import SwiftUI
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
        var closed = 0
        let panel = ItemActionPanel(rows: [
            ItemAction(title: "Open With", symbol: "arrow.up.forward.app", children: [ItemAction(title: "Preview", symbol: "app")]),
            nil,
            ItemAction(title: "Copy Path", symbol: "doc.on.doc"),
            ItemAction(title: "Quick Look", symbol: "eye"),
        ]) { closed += 1 }
        #expect(try panel.handleActionPanelKey(key(35, [], "p"), []))
        #expect(try panel.handleActionPanelKey(key(15, .shift, "R"), [.shift]), "Shift types a capital")
        #expect(panel.panelQuery == "pR")
        #expect(titles(panel) == ["Preview"])
        #expect(panel.panelEntries.allSatisfy { !$0.startsGroup }, "a search lists its matches with no separators")
        #expect(try panel.handleActionPanelKey(key(51), []))
        #expect(titles(panel) == ["Preview", "Copy Path"], "Delete takes the last letter off")
        #expect(try !panel.handleActionPanelKey(key(8, .command, "c"), [.command]), "⌘ keys are not typed into it")
        #expect(try panel.handleActionPanelKey(key(53), []))
        #expect(panel.panelQuery.isEmpty, "Esc clears the search before anything else")
        #expect(closed == 0)
        #expect(try panel.handleActionPanelKey(key(53), []))
        #expect(closed == 1, "then Esc at the top closes it")
    }

    /// As an extension's does: inside a submenu a search looks only under it, and lists rows that run something.
    @Test func aSearchInASubmenuLooksOnlyUnderIt() throws {
        let panel = ItemActionPanel(rows: [
            ItemAction(title: "Open With", symbol: "arrow.up.forward.app", children: [
                ItemAction(title: "Preview", symbol: "app"),
                ItemAction(title: "Code", symbol: "app"),
            ]),
            ItemAction(title: "Copy Path", symbol: "doc.on.doc"),
        ]) {}
        panel.panelQuery = "o"
        #expect(titles(panel) == ["Code", "Copy Path"], "a submenu runs nothing, so it is not a match itself")
        panel.panelQuery = ""
        panel.openPanelSubmenu(at: 0)
        panel.panelQuery = "co"
        #expect(titles(panel) == ["Code"], "not Copy Path, which is outside Open With")
        panel.openPanelSubmenu(at: 0)
        #expect(panel.panelSubmenuTitle == "Open With", "a row that is no submenu opens nothing")
    }

    @Test func thePresenterOpensAndClosesThePanel() {
        let presenter = ActionPanelPresenter()
        presenter.toggle([nil])
        #expect(presenter.panel == nil, "with no rows there is nothing to open")
        presenter.toggle([ItemAction(title: "Copy Path", symbol: "doc.on.doc")])
        #expect(presenter.panel != nil)
        presenter.panel?.closePanel()
        #expect(presenter.panel == nil, "a row run, or Esc at the top, closes it")
        presenter.toggle([ItemAction(title: "Copy Path", symbol: "doc.on.doc")])
        presenter.toggle([ItemAction(title: "Copy Path", symbol: "doc.on.doc")])
        #expect(presenter.panel == nil, "⌘K again closes it")
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
        try #require(model.actionPanel.panel != nil)
        model.panelDidHide()
        #expect(model.actionPanel.panel == nil, "closing the launcher closes its Actions menu")
    }

    /// ⌘K reaches the panel through what the Actions button registers while its view is on screen.
    @Test func commandKOpensAndClosesThePanelOfTheViewOnScreen() throws {
        let model = try openPanel()
        model.actionPanel.close()
        let registration = NSHostingView(rootView: ActionsRegistration(model: model) { $0.selectedRootItem.map($0.rootActions) ?? [] })
        registration.layoutSubtreeIfNeeded()
        #expect(try model.handlePanelKey(key(40, .command, "k"), layout: .extended))
        #expect(model.actionPanel.panel?.panelEntries.first?.title == "Open")
        #expect(try model.handlePanelKey(key(40, .command, "k"), layout: .extended))
        #expect(model.actionPanel.panel == nil)
        withExtendedLifetime(registration) {}
    }

    // MARK: - Drawn

    private func laidOut(_ view: some View, width: CGFloat = 500, height: CGFloat = 400) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test func theCardDrawsEveryKindOfRowAndFitsAShortPanel() {
        let rows: [ActionPanelEntry] = [
            ActionPanelEntry(id: 0, title: "Open", icon: .symbol("return"), section: "Primary", keys: .combination(KeyCombination(key: .returnKey, modifiers: .command))),
            ActionPanelEntry(id: 1, title: "Open With", icon: .symbol("app"), startsGroup: true, isSubmenu: true),
            ActionPanelEntry(id: 2, title: "Copy", icon: .symbol("doc.on.doc"), keys: .label("⌘C")),
            ActionPanelEntry(id: 3, title: "Delete", icon: .symbol("trash"), isDestructive: true),
        ] + (4 ..< 30).map { ActionPanelEntry(id: $0, title: "Row \($0)", icon: .symbol("circle")) }
        let card = ActionPanelCard(entries: rows, query: "", submenuTitle: "More", selection: 1, room: 200) { _ in }
        let host = laidOut(card)
        #expect(host.fittingSize.height <= 200, "thirty rows scroll inside the room instead of running past it")
        let empty = laidOut(ActionPanelCard(entries: [], query: "zz", submenuTitle: nil, selection: 0) { _ in })
        #expect(empty.fittingSize.height > 0, "no match still draws the search line and says so")
    }

    @Test func theOverlayDrawsThePanelOnlyWhileItIsOpen() {
        let presenter = ActionPanelPresenter()
        let closed = laidOut(Color.clear.actionPanel(presenter))
        presenter.toggle([ItemAction(title: "Copy Path", symbol: "doc.on.doc"), ItemAction(title: "Preview", symbol: "app", icon: NSImage(size: NSSize(width: 16, height: 16)))])
        closed.layoutSubtreeIfNeeded()
        #expect(presenter.panel?.panelEntries.count == 2)
        closed.rootView = AnyView(Color.clear)
        closed.layoutSubtreeIfNeeded()
        #expect(presenter.panel == nil, "the rows were that view's: another view would draw or take keys over them")
        withExtendedLifetime(closed) {}
    }
}
