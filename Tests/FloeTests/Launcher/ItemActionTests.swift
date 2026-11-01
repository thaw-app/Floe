//
//  ItemActionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing
import ThawUI

@MainActor
struct ItemActionTests {
    private let host = ActionHost(showHUD: { _ in }, dismiss: {})

    private func titles(_ actions: [ItemAction?]) -> [String] {
        actions.map { $0?.title ?? "-" }
    }

    private func makeModel(apps: [AppEntry] = []) -> LauncherModel {
        let settings = AppSettings(defaults: MemoryDefaults())
        return LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: apps, commands: []))
    }

    @Test func theDefaultAppLeadsTheOpenWithListAndNoAppRepeats() {
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let zed = URL(fileURLWithPath: "/Applications/Zed.app")
        let acorn = URL(fileURLWithPath: "/Applications/Acorn.app")
        let ordered = FileActions.orderedApps([zed, preview, acorn, zed], preferred: preview)
        #expect(ordered == [preview, acorn, zed])
        #expect(FileActions.orderedApps([zed, acorn], preferred: nil) == [acorn, zed])
    }

    @Test func aFileOutsideTheSystemCanBeMovedToTheTrashAndOneInsideCannot() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-action-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FileActions.canTrash(file))
        #expect(!FileActions.canTrash(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        #expect(titles(FileActions.actions(for: file, host: host)).suffix(2) == ["-", "Move to Trash…"])
    }

    @Test func aFileOffersItsCopiesAndAlwaysShowInFinder() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-action-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let listed = titles(FileActions.actions(for: file, host: host))
        for expected in ["Show in Finder", "Copy Path", "Copy Name", "Copy File"] {
            #expect(listed.contains(expected), "\(expected) is offered for a file")
        }
    }

    @Test func quickLookHandsTheFileToTheHost() {
        let file = URL(fileURLWithPath: "/tmp/floe-quick-look.txt")
        var shown: [URL] = []
        var host = ActionHost(showHUD: { _ in }, dismiss: {})
        host.quickLook = { shown.append($0) }
        let action = FileActions.actions(for: file, host: host).compactMap(\.self).first { $0.title == "Quick Look" }
        action?.run()
        #expect(shown == [file])
    }

    @Test func anAppThatIsNotRunningOffersNoQuitAndASystemAppNoTrash() {
        let app = AppEntry(name: "Floe Test App", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))
        let listed = titles(AppActions.actions(for: app, host: host))
        #expect(!listed.contains("Quit"))
        #expect(!listed.contains("Force Quit…"))
        #expect(!listed.contains("Move to Trash…"))
        #expect(!listed.contains("Copy File"), "an app's bundle is not something to paste")
        #expect(listed.contains("Show in Finder"))
        #expect(listed.contains("Copy Path"))
    }

    @Test func aMenuNestsChildrenAndDrawsSeparators() {
        let menu = ActionsMenu.menu([
            ItemAction(title: "Open With", symbol: "arrow.up.forward.app", children: [ItemAction(title: "Preview", symbol: "app")]),
            nil,
            ItemAction(title: "Copy Path", symbol: "doc.on.doc"),
        ])
        #expect(menu.items.map(\.title) == ["Open With", "", "Copy Path"])
        #expect(menu.items[0].submenu?.items.map(\.title) == ["Preview"])
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[2].submenu == nil)
    }

    @Test func aRowsKeysAreDrawnBesideItInASubmenuToo() {
        let menu = ActionsMenu.menu([
            ItemAction(title: "Show in Finder", symbol: "folder", shortcut: KeyCombination(key: .returnKey, modifiers: .command)),
            ItemAction(title: "Add to Favorites", symbol: "star", shortcut: KeyCombination(key: .f, modifiers: [.command, .shift])),
            ItemAction(title: "More", symbol: "ellipsis", children: [ItemAction(title: "Quick Look", symbol: "eye", shortcut: KeyCombination(key: .y, modifiers: .command))]),
            ItemAction(title: "Copy Name", symbol: "textformat"),
            ItemAction(title: "Copy File", symbol: "doc.on.clipboard", shortcut: KeyCombination(key: .f5, modifiers: .command)),
            ItemAction(title: "Move to Trash…", symbol: "trash", shortcut: KeyCombination(key: .keypad1, modifiers: .command)),
        ])
        #expect(menu.items[0].keyEquivalent == "\r", "Return is drawn as Return on any layout")
        #expect(menu.items[0].keyEquivalentModifierMask == .command)
        #expect(menu.items[1].keyEquivalent == KeyCode.f.keyEquivalent, "a letter is what the key types on this Mac")
        #expect(menu.items[1].keyEquivalentModifierMask == [.command, .shift])
        #expect(menu.items[2].submenu?.items.first?.keyEquivalent == KeyCode.y.keyEquivalent)
        #expect(menu.items[3].keyEquivalent.isEmpty)
        #expect(menu.items[4].keyEquivalent == String(utf16CodeUnits: [unichar(NSF5FunctionKey)], count: 1), "a function key is itself")
        #expect(menu.items[5].keyEquivalentModifierMask == [.command, .numericPad], "a keypad key is the keypad's, not the main row's")
    }

    @Test func rootActionsStartWithOpenAndEndWithTheFavoriteToggle() {
        let safari = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))
        let model = makeModel(apps: [safari])
        let item = RootItem.app(safari)

        #expect(titles(model.rootActions(for: item)).first == "Open")
        #expect(titles(model.rootActions(for: item)).suffix(2) == ["Add to Favorites", "Hide from Search"])
        model.toggleFavorite(item)
        #expect(titles(model.rootActions(for: item)).suffix(2) == ["Remove from Favorites", "Hide from Search"])
    }

    @Test func aResultThatIsGoneNextTimeHasNoFavoriteToggle() {
        let model = makeModel()
        #expect(titles(model.rootActions(for: .calculator(expression: "2+2", result: "4"))) == ["Open"])
        #expect(titles(model.rootActions(for: .searchFiles("notes"))) == ["Open"])
        #expect(titles(model.rootActions(for: .system(.toggleMute))).suffix(2) == ["Add to Favorites", "Hide from Search"])
    }

    @Test func returnOnACalculationWithNothingToCopySaysSo() {
        let model = makeModel()
        var said: [String] = []
        model.panelHost.showHUD = { said.append($0) }
        model.activate(.calculator(expression: "100 +", result: "", error: nil, attributedResult: nil))
        model.activate(.calculator(expression: "1 km to kg", result: "", error: "Cannot convert Length to Mass", attributedResult: nil))
        #expect(said == ["Nothing to copy yet", "Cannot convert Length to Mass"])
    }

    @Test func aHiddenResultLeavesTheListTheSearchAndTheFavorites() {
        let safari = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))
        let notes = AppEntry(name: "Notes", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))
        let model = makeModel(apps: [safari, notes])
        let item = RootItem.app(safari)
        model.toggleFavorite(item)

        model.hideFromSearch(item)
        #expect(model.settings.hiddenResults == [item.id: "Safari"], "kept with its title, for Settings to list it by")
        #expect(model.settings.favorites.isEmpty)
        #expect(!model.results.contains { $0.id == item.id })
        model.query = "saf"
        #expect(!model.results.contains { $0.id == item.id })
        model.query = "notes"
        #expect(model.results.contains { $0.id == RootItem.app(notes).id }, "nothing else is hidden with it")

        model.settings.hiddenResults = [:]
        model.query = "saf"
        #expect(model.results.contains { $0.id == item.id }, "shown again once it is taken off the list")
    }

    @Test func theExtensionStoreIsFoundInTheSearchAndOpensItsSettingsPage() {
        let model = makeModel()
        var hidden = 0
        var opened: [SettingsPage?] = []
        model.panelHost.hidePanel = { hidden += 1 }
        model.panelHost.openSettings = { opened.append($0) }

        for query in ["store", "extension store", "install", "raycast"] {
            model.query = query
            #expect(model.results.contains { $0.id == "extension-store" }, "\(query)")
        }
        let row = RootItem.extensionStore
        #expect(row.title == "Extension Store")
        #expect(row.kind == "Floe")

        model.activate(row)
        #expect(opened == [.extensionStore])
        #expect(hidden == 1)
        #expect(SettingsPage.extensionStore.id == "store", "the page the settings process is asked for")

        model.activate(.settings)
        #expect(opened == [.extensionStore, nil], "Floe Settings still opens where it was left")
    }

    @Test func theWayIntoSettingsAndWhatIsGoneNextTimeCannotBeHidden() {
        let model = makeModel()
        #expect(!LauncherModel.canBeHidden(.settings))
        #expect(!LauncherModel.canBeHidden(.calculator(expression: "2+2", result: "4")))
        #expect(!LauncherModel.canBeHidden(.definition(WordDefinition(word: "tide", entry: "the sea rises"))), "an answer is gone with its query")
        #expect(LauncherModel.canBeHidden(.system(.toggleMute)))
        #expect(!titles(model.rootActions(for: .settings)).contains("Hide from Search"))
        model.hideFromSearch(.settings)
        #expect(model.settings.hiddenResults.isEmpty)
    }

    private func scratchDefaults() -> UserDefaults {
        MemoryDefaults()
    }

    @Test func aSearchIsRememberedOnceAndTheOldestGivesWay() {
        let defaults = scratchDefaults()
        let usage = UsageStore(defaults: defaults)
        usage.recordQuery("  safari ")
        usage.recordQuery("12 * 4")
        usage.recordQuery("   ")
        usage.recordQuery("safari")
        #expect(usage.queries == ["12 * 4", "safari"], "typed again, it moves to the newest place")
        #expect(UsageStore(defaults: defaults).queries == ["12 * 4", "safari"], "kept for the next launch")

        for number in 0 ..< UsageStore.queryLimit {
            usage.recordQuery("search \(number)")
        }
        #expect(usage.queries.count == UsageStore.queryLimit)
        #expect(usage.queries.first == "search 0")

        usage.forgetQueries()
        #expect(usage.queries.isEmpty)
        #expect(UsageStore(defaults: defaults).queries.isEmpty)
    }

    @Test func upAtTheTopWalksBackThroughEarlierSearches() {
        let usage = UsageStore(defaults: scratchDefaults())
        let settings = AppSettings(defaults: scratchDefaults())
        let model = LauncherModel(settings: settings, usage: usage, snapshot: CatalogSnapshot(apps: [], commands: []))
        #expect(!model.recallOlderQuery(), "nothing to bring back yet")

        usage.recordQuery("notes")
        usage.recordQuery("12 * 4")
        #expect(model.recallOlderQuery())
        #expect(model.query == "12 * 4")
        #expect(model.recallOlderQuery())
        #expect(model.query == "notes")
        #expect(model.recallOlderQuery(), "at the oldest the key is still used, and nothing changes")
        #expect(model.query == "notes")

        model.query = "notes app"
        #expect(!model.recallOlderQuery(), "a search the user typed is left alone")
        #expect(model.query == "notes app")

        model.reset()
        #expect(model.recallOlderQuery())
        #expect(model.query == "12 * 4", "a closed launcher starts from the newest again")

        model.query = "calendar"
        model.rememberQuery()
        #expect(usage.queries.last == "calendar")
        settings.remembersSearches = false
        model.query = "secret"
        model.rememberQuery()
        #expect(usage.queries.last == "calendar", "nothing is kept once it is switched off")
    }

    @Test func returnConfirmsADestructiveQuestionAndEscapeCancelsIt() {
        let alert = Confirm.destructiveAlert("Empty Trash", detail: "Empty the Trash? This can't be undone.", button: "Empty Trash")
        let confirm = alert.buttons[0]
        #expect(confirm.hasDestructiveAction, "the button still reads as one that cannot be taken back")
        #expect(confirm.keyEquivalent == "\r", "the command was run from the keyboard, so Return answers it")
        #expect(alert.buttons[1].keyEquivalent == "\u{1B}")
    }

    @Test func onlyTheRedButtonGoesAhead() {
        #expect(Confirm.destructive("Empty Trash", detail: "", button: "Empty Trash") { _ in .alertFirstButtonReturn })
        #expect(!Confirm.destructive("Empty Trash", detail: "", button: "Empty Trash") { _ in .alertSecondButtonReturn }, "Cancel")
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func aQuestionInThePanelGoesAheadOnReturnAndNotOnEscape() throws {
        let model = makeModel()
        var shown = 0
        model.panelHost.showPanel = { shown += 1 }
        var went = 0
        let question = PanelQuestion(title: "Empty Trash", detail: "", button: "Empty Trash") { went += 1 }
        model.ask(question)
        #expect(shown == 1, "a command run by its hotkey brings the panel up for its question")
        #expect(try model.handlePanelKey(key(0), layout: .extended), "a letter is held back while the question is up")
        #expect(model.question != nil && model.query.isEmpty)
        #expect(try model.handlePanelKey(key(53), layout: .extended))
        #expect(model.question == nil && went == 0, "Escape is no")
        model.ask(question)
        #expect(try model.handlePanelKey(key(36), layout: .extended))
        #expect(model.question == nil && went == 1, "Return is yes")
        model.ask(question)
        model.panelDidHide()
        #expect(model.question == nil && went == 1, "closing the panel is no answer to go ahead on")
    }

    @Test func emptyTrashAsksInThePanelBeforeTheMacIsTouched() {
        let kept = Confirm.inPanel
        defer { Confirm.inPanel = kept }
        var asked: [PanelQuestion] = []
        Confirm.inPanel = { asked.append($0) }
        let rows = SystemRows()
        var left = 0
        rows.host.leave = { left += 1 }
        rows.run(.emptyTrash)
        #expect(asked.map(\.title) == ["Empty Trash"])
        #expect(asked.first?.button == "Empty Trash")
        #expect(left == 0, "the panel stays up for the question")
    }
}

/// The names settings will keep the user's choices under.
@MainActor
struct ActionIDTests {
    private let host = ActionHost(showHUD: { _ in }, dismiss: {})

    private func makeModel(apps: [AppEntry] = []) -> LauncherModel {
        LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: apps, commands: []))
    }

    /// Every row, a submenu's rows included.
    private func flattened(_ actions: [ItemAction?]) -> [ItemAction] {
        actions.compactMap(\.self).flatMap { [$0] + flattened($0.children) }
    }

    /// Settings will keep what the user chose under these names, so a renamed one loses it.
    @Test func floesOwnActionIDsKeepTheirNames() {
        let names: [ActionID: String] = [
            .primary: "floe:primary", .showInFinder: "floe:showInFinder", .quickLook: "floe:quickLook",
            .moveToTrash: "floe:moveToTrash", .copyPath: "floe:copyPath", .copyName: "floe:copyName",
            .copyFile: "floe:copyFile", .copyBundleIdentifier: "floe:copyBundleIdentifier",
            .copyAddress: "floe:copyAddress", .copy: "floe:copy", .hide: "floe:hide", .quit: "floe:quit",
            .restart: "floe:restart", .forceQuit: "floe:forceQuit", .configureExtension: "floe:configureExtension",
            .toggleFavorite: "floe:toggleFavorite", .hideFromSearch: "floe:hideFromSearch", .openWith: "floe:openWith",
            .openIn(.terminal): "floe:openIn/terminal",
        ]
        for (id, name) in names {
            #expect(id.rawValue == name)
        }
        #expect(ActionID.openWith(URL(fileURLWithPath: "/System/Applications/NotARealApp.app")).rawValue == "floe:openWith//System/Applications/NotARealApp.app")
    }

    @Test func theCopyMacOSOpensIsNamedByItsBundleIdentifierAndAnyOtherByItsPath() {
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let copy = URL(fileURLWithPath: "/tmp/floe-copy-\(UUID().uuidString)/Preview.app")
        guard Bundle(url: preview)?.bundleIdentifier == "com.apple.Preview" else { return }
        let contents = copy.appendingPathComponent("Contents")
        try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: preview.appendingPathComponent("Contents/Info.plist"), to: contents.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        let systemOpens: (String) -> URL? = { $0 == "com.apple.Preview" ? preview : nil }
        #expect(ActionID.openWith(preview, systemCopy: systemOpens).rawValue == "floe:openWith/com.apple.Preview")
        #expect(ActionID.openWith(copy, systemCopy: systemOpens).rawValue == "floe:openWith/" + copy.resolvingSymlinksInPath().path)
        #expect(ActionID.openWith(copy, systemCopy: { _ in copy }).rawValue == "floe:openWith/com.apple.Preview", "the copy macOS opens is the one named by the identifier")
    }

    @Test func anActionIDIsStoredAsItsName() throws {
        let data = try JSONEncoder().encode([ActionID.quit])
        #expect(String(bytes: data, encoding: .utf8) == #"["floe:quit"]"#)
        #expect(try JSONDecoder().decode([ActionID].self, from: data) == [.quit])
    }

    @Test func everyRowOfAFilesMenuIsNamedOnce() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-action-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let rows = flattened(FileActions.actions(for: file, host: host))
        let ids = rows.compactMap(\.id)
        #expect(ids.count == rows.count, "every row has an id")
        #expect(Set(ids).count == ids.count, "no two rows share one")
        #expect(ids.allSatisfy { $0.rawValue.hasPrefix("floe:") })
        let named = Dictionary(rows.map { ($0.title, $0.id) }, uniquingKeysWith: { first, _ in first })
        let expected: [String: ActionID] = [
            "Show in Finder": .showInFinder, "Quick Look": .quickLook, "Copy Path": .copyPath, "Copy Name": .copyName,
            "Copy File": .copyFile, "Move to Trash…": .moveToTrash, "Open With": .openWith,
        ]
        for (title, id) in expected {
            #expect(named[title] == id, "\(title) is \(id.rawValue)")
        }
    }

    @Test func everyRowOfAnAppsMenuIsNamedOnce() {
        let app = AppEntry(name: "Floe Test App", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))
        let model = makeModel(apps: [app])
        let rows = flattened(model.rootActions(for: .app(app)))
        let ids = rows.compactMap(\.id)
        #expect(ids.count == rows.count, "every row has an id")
        #expect(Set(ids).count == ids.count, "no two rows share one")
        #expect(ids.first == .primary)
        #expect(ids.suffix(2) == [.toggleFavorite, .hideFromSearch])
    }
}
