//
//  ThawIntegrationTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ThawIntegrationTests {
    @Test func everyActionIsALinkThawAnswers() {
        let links = Dictionary(uniqueKeysWithValues: ThawAction.allCases.map { ($0, $0.url?.absoluteString) })
        #expect(links[.toggleHidden] == "thaw://toggle-hidden")
        #expect(links[.toggleAlwaysHidden] == "thaw://toggle-always-hidden")
        #expect(links[.toggleSwap] == "thaw://toggle-swap")
        #expect(links[.search] == "thaw://search")
        #expect(links[.itemHints] == "thaw://item-hints")
        #expect(links[.toggleThawBar] == "thaw://toggle-thawbar")
        #expect(links[.toggleApplicationMenus] == "thaw://toggle-application-menus")
        #expect(links[.toggleZenMode] == "thaw://toggle-zen-mode")
        #expect(links[.toggleLayoutEditor] == "thaw://toggle-layout-editor")
        #expect(links[.openSettings] == "thaw://open-settings")
        #expect(links[.toggleAutoRehide] == "thaw://toggle?key=autoRehide")
        #expect(links[.toggleShowOnHover] == "thaw://toggle?key=showOnHover")
        #expect(links[.toggleHideApplicationMenus] == "thaw://toggle?key=hideApplicationMenus")
        #expect(links[.authorize] == "thaw://authorize")
        #expect(links.count == ThawAction.allCases.count, "an action added later needs its link checked here")
    }

    @Test func titlesAreDistinctAndOnlyTheSettingTogglesNeedThawsApproval() {
        #expect(Set(ThawAction.allCases.map(\.title)).count == ThawAction.allCases.count)
        #expect(ThawAction.allCases.filter(\.changesASetting) == [.toggleAutoRehide, .toggleShowOnHover, .toggleHideApplicationMenus])
    }

    @Test func theActionsAreListedOnlyWhenThawIsInstalled() {
        #expect(Thaw.actions(isInstalled: false).isEmpty)
        #expect(Thaw.actions(isInstalled: true) == ThawAction.allCases)
    }

    @Test func typingThawFindsEveryActionAndTheirKindSaysWhoseTheyAre() {
        let items = ThawAction.allCases.map(RootItem.thaw)
        let results = Ranking.search(items, query: "thaw", favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(Set(results.map(\.item.id)) == Set(items.map(\.id)))
        #expect(items.allSatisfy { $0.kind == "Thaw" })
        #expect(RootItem.thaw(.toggleSwap).id == "thaw:toggleSwap")
    }

    @Test func settingsSayWhereTheActionsAreOrHowToGetThem() {
        #expect(MenuBarAppSetting.detail(for: .thaw, isInstalled: true).contains("type “thaw”"))
        #expect(MenuBarAppSetting.detail(for: .thaw, isInstalled: false) == "Install Thaw and its actions appear in the search.")
    }
}
