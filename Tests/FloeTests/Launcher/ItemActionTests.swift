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

@MainActor
struct ItemActionTests {
    private let host = ActionHost(showHUD: { _ in }, dismiss: {})

    private func titles(_ actions: [ItemAction?]) -> [String] {
        actions.map { $0?.title ?? "-" }
    }

    private func makeModel(apps: [AppEntry] = []) -> LauncherModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "floe-action-tests-\(UUID().uuidString)")!)
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

    @Test func rootActionsStartWithOpenAndEndWithTheFavoriteToggle() {
        let safari = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))
        let model = makeModel(apps: [safari])
        let item = RootItem.app(safari)

        #expect(titles(model.rootActions(for: item)).first == "Open")
        #expect(titles(model.rootActions(for: item)).last == "Add to Favorites")
        model.toggleFavorite(item)
        #expect(titles(model.rootActions(for: item)).last == "Remove from Favorites")
    }

    @Test func aResultThatIsGoneNextTimeHasNoFavoriteToggle() {
        let model = makeModel()
        #expect(titles(model.rootActions(for: .calculator(expression: "2+2", result: "4"))) == ["Open"])
        #expect(titles(model.rootActions(for: .searchFiles("notes"))) == ["Open"])
        #expect(titles(model.rootActions(for: .system(.toggleMute))).last == "Add to Favorites")
    }
}
