//
//  MenuItemSearchTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Synchronization
import Testing

/// The front app's menus, as a scan of Preview's would return them.
private nonisolated enum Menus {
    static let preview = MenuTarget(pid: 4242, name: "Preview", url: nil)
    static let mail = MenuTarget(pid: 4343, name: "Mail", url: nil)

    static func item(_ path: [String], _ indices: [Int], key: String? = nil, enabled: Bool = true) -> AppMenuItem {
        AppMenuItem(
            title: path.last ?? "",
            path: path,
            indices: indices,
            shortcut: key.map { MenuShortcut(keyChar: $0, modifiers: 0, virtualKey: nil) },
            enabled: enabled
        )
    }

    static let items = [
        item(["File", "Open…"], [1, 1], key: "o"),
        item(["File", "Export as PDF…"], [1, 6]),
        item(["File", "Export", "PNG"], [1, 7, 0]),
        item(["File", "Print…"], [1, 9], key: "p", enabled: false),
        item(["Edit", "Copy"], [2, 4], key: "c"),
        item(["View", "Actual Size"], [3, 2], key: "0"),
    ]
}

@MainActor struct MenuItemRankingTests {
    @Test func withoutAQueryEveryCommandThatCanBeChosenIsListedInMenuOrder() {
        #expect(MenuItems.ranked(Menus.items, query: "").map(\.title) == ["Open…", "Export as PDF…", "PNG", "Copy", "Actual Size"])
    }

    @Test func aDisabledCommandIsNotOfferedEvenWhenItMatches() {
        #expect(MenuItems.ranked(Menus.items, query: "print").isEmpty)
    }

    @Test func theTitleMatchesBeforeTheMenusItSitsIn() {
        let ranked = MenuItems.ranked(Menus.items, query: "export").map(\.title)
        #expect(ranked == ["Export as PDF…", "PNG"], "PNG is found through its Export submenu, after the title that says it")
        #expect(MenuItems.ranked(Menus.items, query: "edit").map(\.title) == ["Copy"], "a menu's name finds its commands")
        #expect(MenuItems.ranked(Menus.items, query: "zzz").isEmpty)
    }
}

@MainActor struct MenuItemSearchModelTests {
    private func environment(
        front: MenuTarget? = Menus.preview,
        trusted: Bool = true,
        scans: CallLog = CallLog(),
        chosen: CallLog = CallLog(),
        asked: CallLog = CallLog()
    ) -> MenuItemSearchModel.Environment {
        MenuItemSearchModel.Environment(
            frontApp: { front },
            isTrusted: { trusted },
            askForAccess: { asked.note("ask") },
            scan: { pid in
                scans.note("\(pid)")
                return Menus.items
            },
            choose: { item, target in chosen.note("\(target.name): \(item.displayPath)") }
        )
    }

    private func scanned(_ environment: MenuItemSearchModel.Environment) async -> MenuItemSearchModel {
        let model = MenuItemSearchModel(environment: environment)
        model.scan()
        await model.scanning?.value
        return model
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func theMenusOfTheAppInFrontAreReadOffTheMainThreadAndListed() async {
        let scans = CallLog()
        let model = await scanned(environment(scans: scans))
        #expect(scans.all == ["4242"])
        #expect(model.target == Menus.preview)
        #expect(!model.isScanning)
        #expect(model.results.count == 5)
    }

    @Test func aQueryNarrowsTheCommandsAndPutsTheSelectionBackOnTheFirst() async {
        let model = await scanned(environment())
        model.selection = 3
        model.query = "copy"
        #expect(model.results.map(\.title) == ["Copy"])
        #expect(model.selection == 0)
        #expect(model.selectedEntry?.shortcut?.label == "⌘C")
    }

    @Test func returnHidesTheLauncherThenChoosesTheCommandInTheAppItCameFrom() async throws {
        let chosen = CallLog()
        let model = await scanned(environment(chosen: chosen))
        let order = CallLog()
        model.host.dismiss = { order.note("dismiss") }
        model.query = "png"
        #expect(try model.handleKey(key(36), []))
        #expect(order.all == ["dismiss"])
        #expect(chosen.all == ["Preview: File > Export > PNG"])
    }

    @Test func theArrowsMoveTheSelectionAndEscapeClearsTheQueryBeforeLeaving() async throws {
        let model = await scanned(environment())
        var closed = 0
        model.host.close = { closed += 1 }
        #expect(try model.handleKey(key(125), []))
        #expect(model.selection == 1)
        model.query = "copy"
        #expect(try model.handleKey(key(53), []))
        #expect(model.query.isEmpty && closed == 0)
        #expect(try model.handleKey(key(53), []))
        #expect(closed == 1)
        #expect(try !model.handleKey(key(0), []), "a letter goes on to the search field")
    }

    @Test func withFloeInFrontNothingIsReadAndNothingIsChosen() async throws {
        let scans = CallLog()
        let chosen = CallLog()
        let model = await scanned(environment(front: nil, scans: scans, chosen: chosen))
        #expect(model.target == nil)
        #expect(scans.all.isEmpty)
        #expect(model.results.isEmpty)
        model.choose(Menus.items[0])
        #expect(chosen.all.isEmpty)
    }

    @Test func withoutAccessibilityNothingIsReadAndGrantAccessAsksForIt() async {
        let scans = CallLog()
        let asked = CallLog()
        let model = await scanned(environment(trusted: false, scans: scans, asked: asked))
        #expect(!model.accessGranted)
        #expect(scans.all.isEmpty)
        model.requestAccess()
        #expect(asked.all == ["ask"])
    }

    @Test func theLauncherShowsTheSearchAndEscapeInItGoesBackToTheRoot() async throws {
        let defaults = MemoryDefaults()
        let launcher = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        launcher.menuItemEnvironment = environment()
        launcher.activate(.menuItemSearch)
        let search = try #require(launcher.menuItemSearch)
        await search.scanning?.value
        #expect(search.results.count == 5)
        #expect(!launcher.panelState.isRootSearch)

        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.menuItemSearch == nil)
        #expect(launcher.panelState.isRootSearch)
    }

    @Test func theCommandHasAKeyForAnAliasAndAHotkey() {
        #expect(RootItem.menuItemSearch.settingsKey == RootItem.menuItemSearchKey)
        #expect(RootItem.menuItemSearch.title == "Search Menu Items")
        #expect(RootItem.menuItemSearch.kind == "Floe")
        #expect(LauncherModel.hotkeyViews.map(\.id).contains(RootItem.menuItemSearchKey))
    }
}

@MainActor struct MenuItemSearchScopeTests {
    private func scope(trusted: Bool = true, front: @escaping () -> MenuTarget? = { Menus.preview }, scans: CallLog = CallLog()) -> MenuItemSearchScope {
        MenuItemSearchScope(isTrusted: { trusted }, frontApp: front, scan: { pid in
            scans.note("\(pid)")
            return Menus.items
        })
    }

    private func rows(_ scope: MenuItemSearchScope, _ query: String) async -> [RootItem] {
        let context = SearchContext(query: query)
        guard let text = scope.text(in: context) else { return [] }
        guard let updates = scope.updates(for: text, context: context) else { return scope.results(for: text, context: context) }
        var rows: [RootItem] = []
        for await batch in updates {
            rows = batch
        }
        return rows
    }

    @Test func theWordAloneListsTheCommandsAndTextNarrowsThem() async {
        let scope = scope()
        #expect(await rows(scope, "menus").map(\.title) == ["Open…", "Export as PDF…", "PNG", "Copy", "Actual Size"])
        #expect(await rows(scope, "menus copy").map(\.title) == ["Copy"])
        #expect(scope.text(in: SearchContext(query: "menu copy")) == nil, "menu is the menu bar items' word")
    }

    @Test func theMenusAreReadOnceUntilAnotherAppComesToTheFront() async {
        let scans = CallLog()
        var front = Menus.preview
        let scope = scope(front: { front }, scans: scans)
        _ = await rows(scope, "menus")
        #expect(await rows(scope, "menus open").map(\.title) == ["Open…"], "the last read answers at once")
        #expect(scans.all == ["4242"])
        front = Menus.mail
        #expect(scope.results(for: "", context: SearchContext(query: "menus")).isEmpty, "Preview's commands are not offered as Mail's")
        _ = await rows(scope, "menus")
        #expect(scans.all == ["4242", "4343"])
    }

    @Test func typingWhileTheMenusAreReadWaitsForThatReadAndShowsTheNewestQuery() async {
        let scans = CallLog()
        let scope = scope(scans: scans)
        let first = SearchContext(query: "menus")
        let second = SearchContext(query: "menus copy")
        let older = scope.updates(for: "", context: first)
        let newer = scope.updates(for: "copy", context: second)
        var olderRows: [RootItem] = []
        for await batch in older ?? AsyncStream { $0.finish() } {
            olderRows = batch
        }
        var newerRows: [RootItem] = []
        for await batch in newer ?? AsyncStream { $0.finish() } {
            newerRows = batch
        }
        #expect(olderRows.isEmpty, "the older search is over")
        #expect(newerRows.map(\.title) == ["Copy"])
        #expect(scans.all == ["4242"])
    }

    @Test func withoutAccessibilityOneRowSaysSo() {
        let scope = scope(trusted: false)
        let context = SearchContext(query: "menus")
        #expect(scope.results(for: "", context: context).map(\.id) == ["menu-item-access"])
        #expect(scope.updates(for: "", context: context) == nil)
    }

    @Test func aRowShowsItsMenusAndShortcutAndKeepsNoPlace() {
        let row = RootItem.menuItem(.item(Menus.items[0], in: Menus.preview))
        #expect(row.title == "Open…")
        #expect(row.subtitle == "File")
        #expect(row.rowLabel == "⌘O")
        #expect(RootItem.menuItem(.item(Menus.items[1], in: Menus.preview)).rowLabel == "Menu Item")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(row))
    }

    @Test func returnOnACommandLeavesTheLauncherThenChoosesIt() {
        let defaults = MemoryDefaults()
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        let rows = model.features.menuItems
        let log = CallLog()
        rows.host.leave = { log.note("leave") }
        rows.choose = { item, target in log.note("\(target.name): \(item.title)") }
        let row = RootItem.menuItem(.item(Menus.items[4], in: Menus.preview))
        #expect(rows.returnTitle(for: row) == "Choose Command")
        #expect(rows.open(row, flags: []))
        #expect(log.all == ["leave", "Preview: Copy"])
        #expect(rows.returnTitle(for: .emojiSearch) == nil)
        #expect(!rows.open(.emojiSearch, flags: []))
    }
}
