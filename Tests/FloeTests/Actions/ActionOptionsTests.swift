//
//  ActionOptionsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing
import ThawUI

/// Apps that are on no Mac, so no test reads the one it runs on.
private enum Fake {
    static let terminal = URL(fileURLWithPath: "/Fake/Applications/Ghostty.app")
    static let editor = URL(fileURLWithPath: "/Fake/Applications/Zed.app")
    static let safari = URL(fileURLWithPath: "/Fake/Applications/Safari.app")
    static let arc = URL(fileURLWithPath: "/Fake/Applications/Arc.app")
    static let roleApps = [RoleApp(role: .terminal, app: ResolvedApp(url: terminal)), RoleApp(role: .editor, app: ResolvedApp(url: editor))]
}

/// Settings lists Floe's own rows of each kind's Actions menu. A row the launcher gains on an app, a file, a folder
/// or a link must be listed too, or nobody could choose it.
@MainActor
struct ActionOptionsTests {
    /// A model on a Mac whose terminal and editor resolve and that has two browsers, so every row is on offer.
    private func makeModel() -> LauncherModel {
        let model = LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.resolvedApps.lookup = AppLookup(
            url: { $0 == AppRole.systemTerminal ? Fake.terminal : nil },
            plainTextApp: { Fake.editor },
            exists: { _ in true },
            bundleIdentifier: { _ in nil },
            appForURL: { Browsers.isWebLink($0) ? Fake.safari : nil },
            browsers: { [Fake.safari, Fake.arc] }
        )
        return model
    }

    /// Every row of a menu, a submenu's included, but not the apps of Open With: those depend on the result, and
    /// Settings lists their submenu instead.
    private func rows(_ menu: [ItemAction?]) -> [ItemAction] {
        menu.compactMap(\.self).flatMap { row in [row] + (row.id == .openWith ? [] : rows(row.children)) }
    }

    /// How a menu and the rows Settings lists for its kind differ: a row not listed, listed with another title or
    /// in another order, or a submenu in one place only.
    private func differences(_ menu: [ItemAction?], kind: SubjectKind, roleApps: [RoleApp]) -> [String] {
        let options = ActionOption.rows(for: kind, roleApps: roleApps)
        let listed = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        let shown = rows(menu).filter { $0.id != nil }
        var found: [String] = []
        for row in shown {
            guard let id = row.id else { continue }
            guard let option = listed[id] else {
                found.append("\(id.rawValue) is not listed")
                continue
            }
            if option.isSubmenu == row.children.isEmpty {
                found.append("\(id.rawValue) is a submenu in one place only")
            }
            // Favorites is named after what it will do to this app; Settings names both at once.
            if id != .toggleFavorite, option.title != row.title {
                found.append("\(id.rawValue) is “\(row.title)” in the menu and “\(option.title)” in Settings")
            }
            if row.shortcut != KindActions().keys(for: id, of: kind) {
                found.append("\(id.rawValue) has other keys in the menu than in Settings")
            }
        }
        let order = shown.compactMap(\.id)
        if options.map(\.id).filter(order.contains) != order {
            found.append("the order differs: \(order.map(\.rawValue))")
        }
        return found
    }

    /// An app bundle with an identifier, in a folder it can be moved out of.
    private func makeApp(in folder: URL) throws -> URL {
        let app = folder.appendingPathComponent("Floe Options Test.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.example.floe-options-\(UUID().uuidString)", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test func everyRowOfAnAppsMenuIsListed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-options-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = makeModel()
        let menu = try model.floeActions(for: .app(AppEntry(name: "Floe Options Test", url: makeApp(in: folder))))
        #expect(menu.contains { $0?.id == .copyBundleIdentifier } && menu.contains { $0?.id == .moveToTrash })
        #expect(differences(menu, kind: .app, roleApps: model.resolvedApps.apps) == [])
    }

    @Test func anAppFoundAsAFileHasItsRowsListed() throws {
        // Typing an app's path, or searching files, finds it as a file: it is an app, with a file's menu.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-options-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try makeApp(in: folder)
        let item = RootItem.file(FileResult(url: app, name: app.lastPathComponent, displayPath: folder.path, contentType: nil, lastUsed: nil))
        #expect(SubjectKind.of(item) == .app)
        let model = makeModel()
        let menu = model.floeActions(for: item)
        #expect(menu.contains { $0?.id == .quickLook } && menu.contains { $0?.id == .copyFile })
        #expect(differences(menu, kind: .app, roleApps: model.resolvedApps.apps) == [])
    }

    @Test func aRunningAppsOwnRowsAreListed() {
        // Hide, Quit, Restart and Force Quit come only with a running app: this test's own process, whose rows are
        // built and never run.
        let entry = AppEntry(name: "Floe Tests", url: Bundle.main.bundleURL)
        let rows = AppActions.processActions(entry, .current, host: ActionHost(showHUD: { _ in }, dismiss: {}))
        #expect(rows.contains { $0.id == .quit } && rows.contains { $0.id == .forceQuit })
        #expect(differences(rows, kind: .app, roleApps: []) == [])
    }

    @Test(arguments: [SubjectKind.file, .folder])
    func everyRowOfAFilesOrAFoldersMenuIsListed(kind: SubjectKind) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-options-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var url = folder
        if kind == .file {
            url = folder.appendingPathComponent("note.txt")
            try Data("x".utf8).write(to: url)
        }
        #expect(SubjectKind.of(url) == kind)
        let model = makeModel()
        let item = RootItem.file(FileResult(url: url, name: url.lastPathComponent, displayPath: folder.path, contentType: nil, lastUsed: nil))
        let menu = model.floeActions(for: item)
        #expect(menu.contains { $0?.id == .openIn(.terminal) } && menu.contains { $0?.id == .openIn(.editor) })
        #expect(differences(menu, kind: kind, roleApps: model.resolvedApps.apps) == [])
    }

    @Test func everyRowOfALinksMenuIsListed() throws {
        let model = makeModel()
        let address = try RootItem.webAddress(#require(WebAddress(typed: "github.com/thaw-app")))
        #expect(SubjectKind.of(address) == .url)
        let menu = model.floeActions(for: address)
        #expect(menu.contains { $0?.id == .openWith }, "the other browser is in Open With")
        #expect(differences(menu, kind: .url, roleApps: model.resolvedApps.apps) == [])
    }

    @Test func whatFloeDoesIsNamedAsTheMenusFirstRowNamesIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-options-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: note)
        let model = makeModel()
        let browser = BrowserMenu(choice: model.settings.browserApp, installed: model.resolvedApps.lookup)
        let results: [(SubjectKind, RootItem)] = try [
            (.app, .app(AppEntry(name: "Floe Options Test", url: makeApp(in: folder)))),
            (.file, .file(FileResult(url: note, name: note.lastPathComponent, displayPath: folder.path, contentType: nil, lastUsed: nil))),
            (.folder, .file(FileResult(url: folder, name: folder.lastPathComponent, displayPath: folder.path, contentType: nil, lastUsed: nil))),
            (.url, .webAddress(#require(WebAddress(typed: "github.com/thaw-app")))),
        ]
        for (kind, item) in results {
            #expect(SubjectKind.of(item) == kind)
            #expect(kind.floeActionTitle(browser: browser) == model.floeActionTitle(for: item), "\(kind.title)")
        }
        #expect(SubjectKind.url.floeActionTitle(browser: browser) == "Open in Safari", "a link opens in the browser chosen")
    }

    @Test func eachKindListsItsRowsInTheMenusOrder() {
        #expect(ActionOption.rows(for: .app, roleApps: Fake.roleApps).map(\.id) == [
            .hide, .quit, .restart, .forceQuit, .openWith, .openIn(.terminal), .openIn(.editor), .showInFinder, .quickLook, .copyPath, .copyName, .copyFile,
            .copyBundleIdentifier, .moveToTrash, .toggleFavorite, .hideFromSearch,
        ])
        let file = ActionOption.rows(for: .file, roleApps: Fake.roleApps)
        #expect(file.map(\.id) == [.openWith, .openIn(.terminal), .openIn(.editor), .showInFinder, .quickLook, .copyPath, .copyName, .copyFile, .moveToTrash])
        #expect(file.prefix(3).map(\.title) == ["Open With", "Open in Ghostty", "Open in Zed"], "a role's row is named after its app now")
        #expect(ActionOption.rows(for: .folder, roleApps: Fake.roleApps) == file)
        #expect(ActionOption.rows(for: .url, roleApps: Fake.roleApps).map(\.id) == [.openWith, .copyAddress])
        let submenus = SubjectKind.allCases.flatMap { ActionOption.rows(for: $0, roleApps: Fake.roleApps) }.filter(\.isSubmenu)
        #expect(Set(submenus.map(\.id)) == [.openWith], "Open With is the one submenu")
        #expect(!ActionOption.rows(for: .file, roleApps: []).contains { $0.id == .openIn(.editor) }, "a role without an app has no row, as in the menu")
        #expect(SubjectKind.allCases.map(\.title) == ["Apps", "Files", "Folders", "Links"])
    }
}

/// What Settings writes when the user picks Return, leaves a row out or records keys.
@MainActor
struct ActionChoiceEditingTests {
    private let rows = ActionOption.rows(for: .file, roleApps: [])
    private let commandO = KeyCombination(key: .o, modifiers: .command)

    @Test func returnDoesOneRowOrWhatFloeDoes() {
        var choices = KindActions()
        #expect(choices.returnChoice(among: rows) == nil)
        choices.setReturnChoice(.copyPath)
        #expect(choices.defaults == [.copyPath])
        #expect(choices.returnChoice(among: rows) == .copyPath)
        choices.setReturnChoice(nil)
        #expect(choices == KindActions())
    }

    @Test func aDefaultThatIsNotListedReadsAsWhatFloeDoes() {
        var choices = KindActions()
        choices.defaults = [.openIn(.editor)]
        #expect(choices.returnChoice(among: rows) == nil, "with no editor the menu has no row for it either, so Return is Floe's")
        choices.defaults = [.openWith, .quickLook]
        #expect(choices.returnChoice(among: rows) == .quickLook, "a submenu does nothing itself, so it is passed over")
    }

    @Test func aRowIsLeftOutOfTheMenuAndBroughtBack() {
        var choices = KindActions()
        choices.setShown(false, for: .quickLook)
        #expect(!choices.shows(.quickLook))
        #expect(choices.hidden == [.quickLook])
        choices.setShown(true, for: .quickLook)
        #expect(choices == KindActions())
    }

    private let commandY = FloeKeys.commandY
    private let commandReturn = KeyCombination(key: .returnKey, modifiers: .command)

    @Test func keysAreGivenAndTakenAway() {
        var choices = KindActions()
        #expect(choices.setKeys(commandO, for: .copyName, of: .file, among: rows) == nil)
        #expect(choices.shortcuts == [.copyName: commandO])
        #expect(choices.keys(for: .copyName, of: .file) == commandO)
        #expect(choices.setKeys(commandO, for: .copyName, of: .file, among: rows) == nil, "a row's own keys again are no clash")
        #expect(choices.setKeys(nil, for: .copyName, of: .file, among: rows) == nil)
        #expect(choices == KindActions())
    }

    @Test func floesKeysAreShownChangedClearedAndGivenBack() {
        var choices = KindActions()
        #expect(choices.keys(for: .quickLook, of: .file) == commandY, "Floe's keys show until they are changed")

        #expect(choices.setKeys(commandO, for: .quickLook, of: .file, among: rows) == nil)
        #expect(choices.keys(for: .quickLook, of: .file) == commandO)

        #expect(choices.setKeys(nil, for: .quickLook, of: .file, among: rows) == nil)
        #expect(choices.keys(for: .quickLook, of: .file) == nil)
        #expect(choices.clearedKeys == [.quickLook] && choices.shortcuts.isEmpty)

        #expect(choices.setKeys(commandY, for: .quickLook, of: .file, among: rows) == nil, "recording Floe's keys again gives them back")
        #expect(choices == KindActions(), "Floe's keys again are nothing chosen")
        #expect(choices.keys(for: .quickLook, of: .file) == commandY)
    }

    @Test func recordingFloesOwnKeysForARowStoresNothing() {
        var choices = KindActions()
        choices.clearedKeys = [.showInFinder]
        #expect(choices.setKeys(commandReturn, for: .showInFinder, of: .file, among: rows) == nil, "⌘↩ is Floe's for the row")
        #expect(choices == KindActions())
    }

    @Test func keysWithReturnCanBeGivenToARow() {
        var choices = KindActions()
        let commandOptionReturn = KeyCombination(key: .returnKey, modifiers: [.command, .option])
        #expect(choices.setKeys(commandOptionReturn, for: .copyName, of: .file, among: rows) == nil)
        #expect(choices.keys(for: .copyName, of: .file) == commandOptionReturn)
        #expect(choices.setKeys(commandReturn, for: .quickLook, of: .file, among: rows) == .taken(commandReturn, by: "Show in Finder"), "⌘↩ is Show in Finder's until it is cleared there")
        _ = choices.setKeys(nil, for: .showInFinder, of: .file, among: rows)
        #expect(choices.setKeys(commandReturn, for: .quickLook, of: .file, among: rows) == nil)
        #expect(choices.keys(for: .quickLook, of: .file) == commandReturn)
    }

    @Test func refusedKeysChangeNothingAndSayWhy() {
        let optionO = KeyCombination(key: .o, modifiers: .option)
        let commandK = KeyCombination(key: .k, modifiers: .command)
        var choices = KindActions()
        _ = choices.setKeys(commandO, for: .copyPath, of: .file, among: rows)
        let before = choices
        let cases: [(KeyCombination, KeyRefusal, String)] = [
            (optionO, .needsCommand(optionO), "\(optionO.displayValue) has no Command key. An action's keys need it, so they never take what you type in the search."),
            (commandK, .reserved(commandK), "\(commandK.displayValue) already does something in the launcher."),
            (commandO, .taken(commandO, by: "Copy Path"), "\(commandO.displayValue) is already the keys for Copy Path."),
            (commandY, .taken(commandY, by: "Quick Look"), "\(commandY.displayValue) is already the keys for Quick Look."),
        ]
        for (keys, refusal, message) in cases {
            let refused = choices.setKeys(keys, for: .copyName, of: .file, among: rows)
            #expect(refused == refusal)
            #expect(refused?.message == message)
            #expect(choices == before)
        }
    }

    @Test func floesKeysAreNotGivenBackWhileAnotherRowHasThem() {
        var choices = KindActions()
        _ = choices.setKeys(commandO, for: .quickLook, of: .file, among: rows)
        _ = choices.setKeys(commandY, for: .copyName, of: .file, among: rows)
        let before = choices
        #expect(choices.setKeys(commandY, for: .quickLook, of: .file, among: rows) == .taken(commandY, by: "Copy Name"))
        #expect(choices == before, "Quick Look keeps ⌘O rather than ending with no keys")
    }

    @Test func floesOwnHotkeysAreNoRowsKeys() {
        let commandSpace = KeyCombination(key: .space, modifiers: .command)
        let optionShiftSpace = KeyCombination(key: .space, modifiers: [.option, .shift])
        let hotkeys: Set = [commandSpace, optionShiftSpace]
        var choices = KindActions()
        let refused = choices.setKeys(optionShiftSpace, for: .copyPath, of: .file, among: rows, hotkeys: hotkeys)
        #expect(refused == .hotkey(optionShiftSpace), "the hotkey that opens Floe is refused as that, not for its missing Command")
        #expect(refused?.message == "\(optionShiftSpace.displayValue) is one of Floe's hotkeys, so it can't also run an action.")
        #expect(choices.setKeys(commandSpace, for: .copyPath, of: .file, among: rows, hotkeys: hotkeys) == .hotkey(commandSpace))
        #expect(choices == KindActions())
        #expect(choices.setKeys(commandSpace, for: .copyPath, of: .file, among: rows) == nil, "without the hotkey it is any keys")
        #expect(choices.keys(for: .copyPath, of: .file, hotkeys: hotkeys) == nil, "and once a hotkey, it runs no row")
    }

    @Test func keysOfARowNoLongerListedDoNotStandInTheWay() {
        var choices = KindActions()
        choices.shortcuts = [.openIn(.editor): commandO]
        #expect(choices.setKeys(commandO, for: .copyName, of: .file, among: rows) == nil, "the editor's row is gone, so nothing could free its keys")
    }

    @Test func floesKeysForARowAreFreeWhereTheKindLacksThemOrTheyWereMoved() {
        var links = KindActions()
        #expect(links.setKeys(commandY, for: .copyAddress, of: .url, among: ActionOption.rows(for: .url, roleApps: [])) == nil, "links have no Quick Look")
        var files = KindActions()
        _ = files.setKeys(commandO, for: .quickLook, of: .file, among: rows)
        #expect(files.setKeys(commandY, for: .copyName, of: .file, among: rows) == nil, "⌘Y is no row's once Quick Look has other keys")
    }

    @Test func aKindSetBackToNothingLeavesTheSettings() {
        var all: [String: KindActions] = [:]
        #expect(all[kind: .file] == KindActions())
        all[kind: .file].setShown(false, for: .quickLook)
        #expect(Array(all.keys) == ["file"])
        all[kind: .file].setShown(true, for: .quickLook)
        #expect(all.isEmpty, "nothing chosen is no entry, so there is nothing to save or sync")
    }
}
