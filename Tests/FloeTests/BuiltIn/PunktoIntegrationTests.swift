//
//  PunktoIntegrationTests.swift
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

struct PunktoIntegrationTests {
    @Test func everyActionIsALinkPunktoAnswers() {
        let links = Dictionary(uniqueKeysWithValues: PunktoAction.allCases.map { ($0, $0.url?.absoluteString) })
        #expect(links[.toggle] == "punkto://toggle")
        #expect(links[.show] == "punkto://show")
        #expect(links[.hide] == "punkto://hide")
        #expect(links.count == PunktoAction.allCases.count, "an action added later needs its link checked here")
    }

    @Test func performingHandsTheLinkToPunktoOnlyWhenItIsInstalled() {
        var opened: [String] = []
        let open = { (url: URL) -> Bool in
            opened.append(url.absoluteString)
            return true
        }
        #expect(Punkto.perform(.show, isInstalled: false, open: open) == .notInstalled)
        #expect(opened.isEmpty)
        #expect(Punkto.perform(.hide, isInstalled: true, open: open) == .opened)
        #expect(opened == ["punkto://hide"])
        #expect(Punkto.perform(.toggle, isInstalled: true, open: { _ in false }) == .notOpened, "installed, but the link did not open")
        #expect(PunktoAction.allCases.map(\.id) == ["toggle", "show", "hide"])
    }

    @Test func eachMenuBarAppIsNamedAsItsMakerNamesIt() {
        #expect(MenuBarApp.allCases.map(\.name) == ["Thaw", "Punkto"])
        #expect(MenuBarApp.allCases.map(\.id) == ["thaw", "punkto"])
    }

    @Test func titlesAreDistinctFromEachOtherAndFromThaws() {
        let punkto = Set(PunktoAction.allCases.map(\.title))
        #expect(punkto.count == PunktoAction.allCases.count)
        #expect(punkto.isDisjoint(with: ThawAction.allCases.map(\.title)))
    }

    @Test func theActionsAreListedOnlyWhenPunktoIsInstalled() {
        #expect(Punkto.actions(isInstalled: false).isEmpty)
        #expect(Punkto.actions(isInstalled: true) == PunktoAction.allCases)
    }

    @Test func typingPunktoFindsEveryActionAndTheirKindSaysWhoseTheyAre() {
        let items = PunktoAction.allCases.map(RootItem.punkto)
        let results = Ranking.search(items, query: "punkto", favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(Set(results.map(\.item.id)) == Set(items.map(\.id)))
        #expect(items.allSatisfy { $0.kind == "Punkto" && $0.settingsKey == nil })
        #expect(RootItem.punkto(.show).id == "punkto:show")
    }

    @Test func theSearchUsesTheChosenAppOrWithoutAChoiceThawBeforePunkto() {
        #expect(MenuBarApp.resolved(chosen: .punkto, thawIsInstalled: true, punktoIsInstalled: false) == .punkto)
        #expect(MenuBarApp.resolved(chosen: .thaw, thawIsInstalled: false, punktoIsInstalled: true) == .thaw)
        #expect(MenuBarApp.resolved(chosen: nil, thawIsInstalled: true, punktoIsInstalled: true) == .thaw)
        #expect(MenuBarApp.resolved(chosen: nil, thawIsInstalled: false, punktoIsInstalled: true) == .punkto)
        #expect(MenuBarApp.resolved(chosen: nil, thawIsInstalled: false, punktoIsInstalled: false) == .thaw)
    }

    @Test func eachSearchListsOnlyTheActionsOfTheMenuBarAppChosenNow() {
        let settings = AppSettings(defaults: MemoryDefaults())
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []))
        settings.menuBarApp = .thaw
        #expect(model.searchContext().punktoActions.isEmpty)
        settings.menuBarApp = .punkto
        let context = model.searchContext()
        #expect(context.thawActions.isEmpty, "a choice changed while Floe is open applies to the next search")
        #expect(context.punktoActions == Punkto.actions())
    }

    @MainActor @Test(arguments: [MenuBarApp.thaw, .punkto, nil])
    func theSettingDrawsForEitherAppInstalledOrNot(chosen: MenuBarApp?) {
        let settings = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        settings.menuBarApp = chosen
        let punkto = URL(fileURLWithPath: "/Applications/Punkto.app")
        let row = Form { MenuBarAppSetting(settings: settings, thawURL: nil, punktoURL: punkto) }.formStyle(.grouped)
        let view = NSHostingView(rootView: row.thawTheme(.floe))
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 200)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
    }

    @Test func settingsSayWhereTheActionsAreOrHowToGetThem() {
        #expect(MenuBarAppSetting.detail(for: .punkto, isInstalled: true).contains("type “punkto”"))
        #expect(MenuBarAppSetting.detail(for: .punkto, isInstalled: false) == "Install Punkto and its actions appear in the search.")
    }

    @Test func theChoiceStaysOnThisMacAndAnImportedOneIsTaken() throws {
        let rule = try #require(SettingsSync.thisMacOnly["menuBarApp"])
        #expect(rule.onImport == .takesFile)
        #expect(!SettingsSync.synced.map(\.name).contains("menuBarApp"))
    }

    @Test func typingThawFindsNoneOfPunktosActions() {
        let items = PunktoAction.allCases.map(RootItem.punkto)
        #expect(Ranking.search(items, query: "thaw", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }).isEmpty)
    }
}
