//
//  ActionKeysTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing
import ThawUI

/// Floe's keys as the Mac running the tests types them: ⌘Y is the key that types y on its layout.
@MainActor
enum FloeKeys {
    static func code(typing character: Character) -> UInt16 {
        UInt16(KeyLayout.current.key(typing: character).rawValue)
    }

    static var commandReturn: KeyCombination {
        KeyCombination(key: .returnKey, modifiers: .command)
    }

    static var commandY: KeyCombination {
        KeyCombination(key: KeyLayout.current.key(typing: "y"), modifiers: .command)
    }

    static var commandShiftC: KeyCombination {
        KeyCombination(key: KeyLayout.current.key(typing: "c"), modifiers: [.command, .shift])
    }

    static var commandShiftF: KeyCombination {
        KeyCombination(key: KeyLayout.current.key(typing: "f"), modifiers: [.command, .shift])
    }
}

/// Floe's keys for the rows of an Actions menu, as the panel meets them.
@MainActor
struct ActionKeysPanelTests {
    private let app = AppEntry(name: "Floe Keys Test", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))

    private func makeModel() -> LauncherModel {
        LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [app], commands: []))
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func commandShiftFAddsAnAppToTheFavoritesAndTakesItOut() throws {
        let model = makeModel()
        model.settings.launcherLayout = .extended
        model.query = "Floe Keys Test"
        model.refresh()
        try #require(model.results.first?.item.id == RootItem.app(app).id)
        model.selection = 0
        #expect(try model.handlePanelKey(key(FloeKeys.code(typing: "f"), [.command, .shift]), layout: .extended))
        #expect(model.settings.favorites == [RootItem.app(app).id])
        #expect(try model.handlePanelKey(key(FloeKeys.code(typing: "f"), [.command, .shift]), layout: .extended))
        #expect(model.settings.favorites.isEmpty)
    }

    @Test func theKeysDoNothingWhileThePanelIsCollapsed() throws {
        let model = makeModel()
        model.settings.launcherLayout = .compact
        model.query = ""
        model.refresh()
        try #require(model.results.indices.contains(model.selection))
        #expect(try model.handlePanelKey(key(FloeKeys.code(typing: "f"), [.command, .shift]), layout: .compact))
        #expect(model.settings.favorites.isEmpty, "collapsed, the panel shows no row for the keys to act on")
    }

    private func keysOnRows(_ rows: [ItemAction?]) -> [ActionID: KeyCombination] {
        let all = rows.compactMap(\.self).flatMap { [$0] + $0.children }
        return Dictionary(all.compactMap { row in row.id.flatMap { id in row.shortcut.map { (id, $0) } } }, uniquingKeysWith: { first, _ in first })
    }

    @Test func anAppsMenuInTheSearchCarriesItsKeys() {
        let rows = makeModel().rootActions(for: .app(app))
        let expected: [ActionID: KeyCombination] = [
            .showInFinder: FloeKeys.commandReturn,
            .copyPath: FloeKeys.commandShiftC,
            .toggleFavorite: FloeKeys.commandShiftF,
        ]
        #expect(keysOnRows(rows) == expected, "an app in the search has no Quick Look row, so ⌘Y is on none")
    }

    @Test(arguments: [SubjectKind.file, .folder])
    func aFilesOrAFoldersMenuInTheSearchCarriesItsKeys(kind: SubjectKind) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var url = folder
        if kind == .file {
            url = folder.appendingPathComponent("note.txt")
            try Data("x".utf8).write(to: url)
        }
        let file = FileResult(url: url, name: url.lastPathComponent, displayPath: folder.path, contentType: nil, lastUsed: nil)
        #expect(keysOnRows(makeModel().rootActions(for: .file(file))) == ActionKeys.floe(for: kind).keys)
        let search = FileSearchModel()
        defer { search.cancel() }
        #expect(keysOnRows(search.actions(for: file)) == ActionKeys.floe(for: kind).keys, "the same keys in Search Files")
        #expect(search.rowKeys(for: file) == ActionKeys.floe(for: kind))
        #expect(search.rowKeys(for: nil) == ActionKeys.floe(for: .file), "with no file selected, a file's keys are still the search's")
    }

    @Test func aResultWhoseMenuOffersNoFavoritesIsNotMadeOne() {
        let model = makeModel()
        let calculation = RootItem.calculator(expression: "2+2", result: "4")
        #expect(ActionKeys.handle(FloeKeys.commandShiftF, keys: { model.rowKeys(for: calculation) }, rows: { model.rootActions(for: calculation) }), "held back, not typed")
        #expect(model.settings.favorites.isEmpty)
        let command = RootItem.system(.toggleMute)
        #expect(!ActionKeys.handle(FloeKeys.commandReturn, keys: { model.rowKeys(for: command) }, rows: { model.rootActions(for: command) }), "⌘↩ on a command is still Return with ⌘")
    }
}

/// Which rows have Floe's keys on each kind of result, and the one rule the views run them by.
@MainActor
struct ActionKeysTests {
    private let commandReturn = FloeKeys.commandReturn
    private let commandY = FloeKeys.commandY
    private let commandShiftC = FloeKeys.commandShiftC
    private let commandShiftF = FloeKeys.commandShiftF

    private final class Target: NSObject {
        @objc func about() {}
        @objc func settings() {}
    }

    private let kinds: [SubjectKind?] = SubjectKind.allCases + [nil]

    @Test func eachKindOfResultHasItsOwnKeys() {
        let files: [ActionID: KeyCombination] = [.showInFinder: commandReturn, .quickLook: commandY, .copyPath: commandShiftC]
        #expect(ActionKeys.floe(for: .file).keys == files)
        #expect(ActionKeys.floe(for: .folder).keys == files)
        #expect(ActionKeys.floe(for: .app).keys == files.merging([.toggleFavorite: commandShiftF]) { $1 }, "an app found as a file has a file's rows")
        #expect(ActionKeys.floe(for: .url).keys.isEmpty)
        #expect(ActionKeys.floe(for: nil).keys == [.toggleFavorite: commandShiftF], "a command, a Settings row and the rest")
        for kind in kinds {
            let keys = Array(ActionKeys.floe(for: kind).keys.values)
            #expect(Set(keys).count == keys.count, "no two rows of a kind have the same keys")
        }
    }

    /// The main menu takes its keys before the panel sees them, and ⌘K, ⌘, and ⌘[ are the panel's own.
    @Test func everyKeyHasCommandAndNoneIsTheLaunchersOrTheMainMenus() {
        let all = kinds.flatMap { ActionKeys.floe(for: $0).keys.values }
        #expect(all.allSatisfy { $0.modifiers.contains(.command) }, "what is typed into a search is never a row's")
        // The panel takes these by the key pressed, whatever it types.
        let panel = [KeyCode.k, .comma, .leftBracket].map { KeyCombination(key: $0, modifiers: .command) }
        #expect(!all.contains { panel.contains($0) })
        let target = Target()
        let menu = MainMenu.make(target: target, about: #selector(Target.about), settings: #selector(Target.settings), includesWindowMenu: false)
        let taken = Set(menu.items.compactMap(\.submenu).flatMap(\.items).filter { !$0.keyEquivalent.isEmpty }.map { item in
            let capital = item.keyEquivalent != item.keyEquivalent.lowercased()
            return Modifiers(nsEventFlags: item.keyEquivalentModifierMask.union(capital ? .shift : [])).symbolicValue + item.keyEquivalent.lowercased()
        })
        #expect(!taken.isEmpty)
        #expect(taken.isDisjoint(with: all.map { $0.modifiers.symbolicValue + $0.key.keyEquivalent.lowercased() }))
    }

    @Test func keyedRowsCarryTheirKeysASubmenusRowsToo() {
        let rows = ActionKeys.floe(for: .file).keyed([
            ItemAction(title: "Open", symbol: "return", id: .primary),
            nil,
            ItemAction(title: "More", symbol: "ellipsis", children: [ItemAction(title: "Copy Path", symbol: "doc.on.doc", id: .copyPath)]),
            ItemAction(title: "Quick Look", symbol: "eye", id: .quickLook),
            ItemAction(title: "Elsewhere", symbol: "questionmark", shortcut: commandY),
        ])
        #expect(rows[0]?.shortcut == nil, "Return is not one of the table's rows")
        #expect(rows[1] == nil)
        #expect(rows[2]?.children.first?.shortcut == commandShiftC)
        #expect(rows[3]?.shortcut == commandY)
        #expect(rows[4]?.shortcut == nil, "a row is given its keys by its id, so one without an id has none")
    }

    @Test func enterOnTheKeypadIsReturn() {
        #expect(ActionKeys.pressed(76, .command) == commandReturn)
        #expect(ActionKeys.pressed(36, .command) == commandReturn)
        #expect(ActionKeys.pressed(16, .command) == KeyCombination(key: .y, modifiers: .command), "any other key is the key pressed")
    }

    @Test func theKeysRunTheirRowAndOtherwiseAreHeldBackOrLeftToTheView() {
        var ran: [ActionID] = []
        var asked = 0
        var built = 0
        let keys = ActionKeys.floe(for: .file)
        let table = {
            asked += 1
            return keys
        }
        let rows: () -> [ItemAction?] = {
            built += 1
            return [ItemAction(title: "Quick Look", symbol: "eye", id: .quickLook) { ran.append(.quickLook) }]
        }
        #expect(!ActionKeys.handle(KeyCombination(key: .y, modifiers: []), keys: table, rows: rows), "a typed y")
        #expect(asked == 0, "what is typed never reads a file's kind")
        #expect(!ActionKeys.handle(KeyCombination(key: .o, modifiers: .command), keys: table, rows: rows), "keys no row of the kind has")
        #expect(built == 0)
        #expect(ActionKeys.handle(commandY, keys: table, rows: rows, collapsed: true))
        #expect(built == 0 && ran.isEmpty, "collapsed, the row is not on screen")
        #expect(ActionKeys.handle(commandY, keys: table, rows: rows))
        #expect(ran == [.quickLook])
        #expect(ActionKeys.handle(commandShiftC, keys: table, rows: rows), "a kind's keys stay the view's where the result lacks the row")
        #expect(!ActionKeys.handle(commandReturn, keys: table, rows: rows), "and Return with them goes on to what Return does")
        #expect(ran == [.quickLook])
    }
}

/// What kind of result a row is, read from where it is now.
struct SubjectKindTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-kind-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aFileAFolderAndALinkToAFolder() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)
        let inner = folder.appendingPathComponent("Inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: inner)

        #expect(SubjectKind.of(file) == .file)
        #expect(SubjectKind.of(inner) == .folder)
        #expect(SubjectKind.of(link) == .folder, "a link is what it leads to")
        #expect(SubjectKind.of(folder.appendingPathComponent("gone.txt")) == nil, "a file that is gone is nothing")
    }

    @Test func anAppFoundAsAFileIsAnAppAndADocumentPackageIsAFile() throws {
        #expect(SubjectKind.of(URL(fileURLWithPath: "/System/Applications/Calculator.app")) == .app)
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = folder.appendingPathComponent("Letter.rtfd")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        #expect(SubjectKind.of(package) == .file)
    }

    @Test func linksAreURLsAndATabIsNot() throws {
        let address = try #require(WebAddress(typed: "github.com"))
        #expect(SubjectKind.of(.webAddress(address)) == .url)
        #expect(SubjectKind.of(.calculator(expression: "1+1", result: "2")) == nil)
    }
}

/// Floe's letter keys on keyboards other than the one the tests run on.
@MainActor
struct KeyLayoutTests {
    /// The US layout with some keys typing something else.
    private func layout(_ changes: [KeyCode: String]) -> KeyLayout {
        let us = Dictionary(uniqueKeysWithValues: KeyLayout.us.map { ($0.value, String($0.key)) })
        return KeyLayout { changes[$0] ?? us[$0] ?? "" }
    }

    @Test func aLetterIsTheKeyThatTypesIt() {
        #expect(layout([:]).key(typing: "y") == .y)
        let qwertz = layout([.y: "z", .z: "y"])
        #expect(qwertz.key(typing: "y") == .z)
        let files = ActionKeys.floe(for: .file, on: qwertz)
        #expect(files.key(for: .quickLook) == KeyCombination(key: .z, modifiers: .command))
        #expect(!files.keys.values.contains(KeyCombination(key: .y, modifiers: .command)), "⌘ and the key that types z is Undo there")
    }

    @Test func aLetterNoKeyTypesIsItsKeyOnAUSKeyboard() {
        #expect(layout([.f: "ф"]).key(typing: "f") == .f)
    }
}
