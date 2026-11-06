//
//  AlternativeActionsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing
import ThawUI

/// The user's choices, as the launcher's Return, Actions menu and keys meet them.
@MainActor
struct AlternativeActionsTests {
    private let app = AppEntry(name: "Floe Test App", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))

    private func makeModel(_ choices: KindActions? = nil) -> LauncherModel {
        let settings = AppSettings(defaults: MemoryDefaults())
        if let choices {
            settings.actionChoices = [SubjectKind.app.rawValue: choices]
        }
        return LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [app], commands: []))
    }

    private func titles(_ rows: [ItemAction?]) -> [String] {
        rows.map { $0?.title ?? "-" }
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func withNothingChosenReturnAndTheMenuAreFloes() {
        let model = makeModel()
        let item = RootItem.app(app)
        #expect(model.primaryActionTitle(for: item) == "Open")
        #expect(titles(model.rootActions(for: item)) == ["Open"] + titles(model.floeActions(for: item)))
    }

    @Test func aDefaultTakesReturnAndFloesOwnStaysInTheMenu() {
        var choices = KindActions()
        choices.defaults = [.toggleFavorite]
        let model = makeModel(choices)
        let item = RootItem.app(app)

        #expect(model.primaryActionTitle(for: item) == "Add to Favorites")
        let rows = model.rootActions(for: item)
        #expect(rows.first??.id == .primary)
        #expect(titles(rows).prefix(3) == ["Add to Favorites", "-", "Open"], "Floe's own Return comes next, under its own title")
        #expect(!rows.dropFirst().contains { $0?.id == .toggleFavorite }, "the default is the Return row, and not listed twice")

        model.activate(item)
        #expect(model.settings.favorites == [item.id])
        #expect(model.usage.records[item.id]?.count == 1, "an app opened by a default counts as used, as opening it would")
    }

    @Test func returnWithKeysHeldIsStillFloes() {
        var choices = KindActions()
        choices.defaults = [.toggleFavorite]
        let model = makeModel(choices)
        #expect(!model.features.actions.open(.app(app), flags: .command))
    }

    @Test func aDefaultThatIsNotOnOfferLeavesReturnToFloe() {
        var choices = KindActions()
        choices.defaults = [.quit]
        let model = makeModel(choices)
        #expect(model.primaryActionTitle(for: .app(app)) == "Open", "an app that isn't running has no Quit")
        #expect(titles(model.rootActions(for: .app(app))).first == "Open")
    }

    @Test func aHiddenRowLeavesTheMenu() {
        var choices = KindActions()
        choices.hidden = [.hideFromSearch, .copyName]
        let model = makeModel(choices)
        let listed = titles(model.rootActions(for: .app(app)))
        #expect(!listed.contains("Hide from Search") && !listed.contains("Copy Name"))
        #expect(listed.contains("Copy Path"))
    }

    /// The app, found by its name and selected in the full panel.
    private func select(_ model: LauncherModel) throws {
        model.settings.launcherLayout = .extended
        model.query = app.name
        model.refresh()
        try #require(model.results.first?.item.id == RootItem.app(app).id)
        model.selection = 0
    }

    @Test func theUsersKeysRunTheirRowInPlaceOfFloes() throws {
        var choices = KindActions()
        choices.shortcuts = [.toggleFavorite: KeyCombination(key: .o, modifiers: .command)]
        let model = makeModel(choices)
        let item = RootItem.app(app)
        try select(model)
        #expect(try model.handlePanelKey(key(31, .command), layout: .extended))
        #expect(model.settings.favorites == [item.id])
        #expect(model.usage.records[item.id] == nil, "keys run a row as a click in the menu does, and count no use")
        _ = try model.handlePanelKey(key(FloeKeys.code(typing: "f"), [.command, .shift]), layout: .extended)
        #expect(model.settings.favorites == [item.id], "⌘⇧F is no longer Favorites' keys on apps")
        #expect(model.rowKeys(for: .system(.toggleMute)).key(for: .toggleFavorite) == FloeKeys.commandShiftF, "a result with no kind keeps Floe's keys")
    }

    @Test func keysWithReturnRunTheirRowBeforeReturn() throws {
        var choices = KindActions()
        choices.shortcuts = [.toggleFavorite: KeyCombination(key: .returnKey, modifiers: [.command, .option])]
        let model = makeModel(choices)
        let item = RootItem.app(app)
        try select(model)
        #expect(try model.handlePanelKey(key(36, [.command, .option]), layout: .extended))
        #expect(model.settings.favorites == [item.id], "the row ran in place of Return")
        #expect(model.usage.records[item.id] == nil, "and the app was not opened")
        #expect(try model.handlePanelKey(key(76, [.command, .option]), layout: .extended))
        #expect(model.settings.favorites.isEmpty, "Enter on the keypad is Return")
    }

    @Test func aRowLeftOutOfTheMenuKeepsItsKeys() throws {
        var choices = KindActions()
        choices.hidden = [.toggleFavorite]
        let model = makeModel(choices)
        let item = RootItem.app(app)
        #expect(!model.rootActions(for: item).contains { $0?.id == .toggleFavorite })
        try select(model)
        #expect(try model.handlePanelKey(key(FloeKeys.code(typing: "f"), [.command, .shift]), layout: .extended))
        #expect(model.settings.favorites == [item.id])
    }

    @Test func theReturnRowShowsTheKeysOfTheDefaultItStandsFor() {
        var choices = KindActions()
        choices.defaults = [.toggleFavorite]
        let model = makeModel(choices)
        let commandShiftF = FloeKeys.commandShiftF
        let rows = model.rootActions(for: .app(app)).compactMap(\.self)
        #expect(rows.first?.shortcut == commandShiftF)
        #expect(rows.filter { $0.shortcut == commandShiftF }.count == 1, "shown once, the default's own row being the Return row")
    }

    @Test func keysReachTheSelectedRowOnlyWhenItIsOnScreen() throws {
        var choices = KindActions()
        choices.shortcuts = [.toggleFavorite: KeyCombination(key: .o, modifiers: .command)]
        let model = makeModel(choices)
        model.settings.launcherLayout = .compact
        model.query = ""
        model.refresh()
        // The app is listed and selected, so only the collapse keeps the keys from running its row.
        model.selection = try #require(model.results.firstIndex { $0.item.id == RootItem.app(app).id })
        _ = try model.handlePanelKey(key(31, .command), layout: .compact)
        #expect(model.settings.favorites.isEmpty, "collapsed, the panel shows no row for the keys to act on")

        model.settings.launcherLayout = .extended
        model.query = "Floe Test App"
        model.refresh()
        try #require(model.results.first?.item.id == RootItem.app(app).id)
        model.selection = 0
        #expect(try model.handlePanelKey(key(31, .command), layout: .extended))
        #expect(model.settings.favorites == [RootItem.app(app).id])
    }

    @Test func aFileOpenedByADefaultIsNotCounted() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-default-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var choices = KindActions()
        choices.defaults = [.quickLook]
        let model = makeModel()
        model.settings.actionChoices = [SubjectKind.file.rawValue: choices]
        var looked: [URL] = []
        model.features.actions.host.floeActions = { _ in
            var host = ActionHost(showHUD: { _ in }, dismiss: {})
            host.quickLook = { looked.append($0) }
            return FileActions.actions(for: file, host: host)
        }
        let item = RootItem.file(FileResult(url: file, name: file.lastPathComponent, displayPath: file.deletingLastPathComponent().path, contentType: nil, lastUsed: nil))
        model.activate(item)
        #expect(looked == [file])
        #expect(model.usage.records[item.id] == nil, "found just now and gone next time, as Floe's own Return has it")
    }

    @Test func choicesAreKeptWithTheSettings() {
        let defaults = MemoryDefaults()
        var choices = KindActions()
        choices.defaults = [.copyPath]
        choices.hidden = [.copyName]
        let settings = AppSettings(defaults: defaults)
        settings.actionChoices = [SubjectKind.file.rawValue: choices]
        settings.save()
        #expect(AppSettings(defaults: defaults).actionChoices == [SubjectKind.file.rawValue: choices])
    }

    @Test func floesOwnHotkeysAreNoRowsKeys() {
        var choices = KindActions()
        choices.shortcuts = [.copyName: KeyCombination(key: .o, modifiers: .command)]
        let model = makeModel(choices)
        let item = RootItem.app(app)
        model.settings.toggleHotkey = FloeKeys.commandShiftF
        model.settings.commandHotkeys = ["example.command": KeyCombination(key: .o, modifiers: .command)]
        let keys = model.rowKeys(for: item)
        #expect(keys.key(for: .toggleFavorite) == nil, "the hotkey that opens Floe is taken by the Mac first, so Favorites shows none")
        #expect(keys.key(for: .copyName) == nil, "nor can the user's keys be a command's hotkey, however they were stored")
        #expect(!model.rootActions(for: item).contains { $0?.shortcut == FloeKeys.commandShiftF }, "and the menu shows it on no row")
        #expect(model.rowKeys(for: nil).key(for: .toggleFavorite) == nil, "with nothing selected too")
    }

    @Test func theReturnTitleFollowsAFavoriteThatChanged() {
        var choices = KindActions()
        choices.defaults = [.toggleFavorite]
        let model = makeModel(choices)
        let item = RootItem.app(app)
        #expect(model.primaryActionTitle(for: item) == "Add to Favorites")
        model.activate(item)
        #expect(model.settings.favorites == [item.id])
        #expect(model.primaryActionTitle(for: item) == "Remove from Favorites", "the title says what Return does now")
    }

    @Test func theReturnTitleFollowsTheAppAnOpenInRowOpens() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-open-in-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var choices = KindActions()
        choices.defaults = [.openIn(.editor)]
        let model = makeModel()
        model.settings.actionChoices = [SubjectKind.file.rawValue: choices]
        let item = RootItem.file(FileResult(url: file, name: file.lastPathComponent, displayPath: file.deletingLastPathComponent().path, contentType: nil, lastUsed: nil))
        model.settings.editorApp = AppChoice(bundleIdentifier: "com.apple.TextEdit", path: "/System/Applications/TextEdit.app")
        model.resolvedApps.invalidate()
        #expect(model.primaryActionTitle(for: item) == "Open in TextEdit")
        model.settings.editorApp = AppChoice(bundleIdentifier: "com.apple.Preview", path: "/System/Applications/Preview.app")
        // As the launcher does when the setting changes.
        model.resolvedApps.invalidate()
        #expect(model.primaryActionTitle(for: item) == "Open in Preview", "the title says what Return opens now")
    }

    @Test func theReturnTitleFollowsWhatTheResultOffersNow() {
        // Quit is on offer only while the app runs, so the title is worked out again when that changes.
        var running = false
        var quit = KindActions()
        quit.defaults = [.quit]
        let actions = AlternativeActions()
        actions.kindOf = { _ in .app }
        actions.host = AlternativeActions.Host(
            choices: { [SubjectKind.app.rawValue: quit] },
            floeActions: { _ in running ? [ItemAction(title: "Quit", symbol: "xmark.circle", id: .quit) {}] : [] },
            floeTitle: { _ in "Open" },
            offerState: { _ in running ? 1 : 0 }
        )
        let item = RootItem.app(app)
        #expect(actions.returnTitle(for: item) == nil, "while the app isn't running, Return opens it")
        running = true
        #expect(actions.returnTitle(for: item) == "Quit", "once it runs, Return quits it and its button says so")
    }

    /// The bottom bar asks a result's kind on every draw, so it is kept; the rows read it again, as a path can have
    /// become a folder since, and a script on files must not be offered on it.
    @Test func rowsReadTheKindAgain() {
        var kind = SubjectKind.file
        let upload = ScriptCommand(
            file: URL(fileURLWithPath: "/tmp/upload.sh"), title: "Upload", packageName: nil, mode: .silent,
            needsConfirmation: false, icon: nil, arguments: [], subjects: [.file]
        )
        let actions = AlternativeActions()
        actions.kindOf = { _ in kind }
        actions.host = AlternativeActions.Host(scripts: { [upload] })
        let item = RootItem.file(FileResult(url: URL(fileURLWithPath: "/tmp/notes"), name: "notes", displayPath: "", contentType: nil, lastUsed: nil))
        _ = actions.keys(for: item)
        kind = .folder
        #expect(!actions.rows([], for: item).contains { $0?.id == upload.actionID })
    }
}
