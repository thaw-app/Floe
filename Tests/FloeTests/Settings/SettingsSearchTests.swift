//
//  SettingsSearchTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Two extensions as their manifests declare them: "Zeta Tools" with an extension preference and
/// two commands, one of which has its own preference, and "Alpha Notes" from Raycast with one command.
private enum SearchFixture {
    static let zeta: [String: Any] = [
        "name": "zeta-tools",
        "title": "Zeta Tools",
        "icon": "zeta.png",
        "preferences": [["name": "apiToken", "title": "API Token", "description": "Token for the Zeta service.", "type": "password"]],
        "commands": [
            [
                "name": "convert",
                "title": "Convert Units",
                "mode": "view",
                "preferences": [["name": "precision", "title": "Decimal Places", "type": "textfield"]],
            ],
            ["name": "timer", "title": "Start Timer", "mode": "no-view"],
        ],
    ]
    static let alpha: [String: Any] = [
        "name": "alpha-notes",
        "title": "Alpha Notes",
        "commands": [["name": "new-note", "title": "Create Note"]],
    ]

    static var commands: [ExtensionCommand] {
        ExtensionCommand.commands(inManifest: Fixture.manifest(zeta), folder: URL(fileURLWithPath: "/tmp/zeta-tools"), source: .local)
            + ExtensionCommand.commands(inManifest: Fixture.manifest(alpha), folder: URL(fileURLWithPath: "/tmp/alpha-notes"), source: .raycast)
    }

    /// One extension with more commands than the search shows at once.
    static func manyCommands(_ count: Int) -> [ExtensionCommand] {
        let manifest: [String: Any] = [
            "name": "bulk",
            "title": "Bulk",
            "commands": (0 ..< count).map { ["name": "c\($0)", "title": "Widget \($0)"] },
        ]
        return ExtensionCommand.commands(inManifest: Fixture.manifest(manifest), folder: URL(fileURLWithPath: "/tmp/bulk"), source: .local)
    }
}

struct SearchRankerTests {
    @Test func relevanceSortPutsTheLowestDiffScoreFirst() {
        let sorted = SearchRanker.sortedByRelevance([(item: "far", diffScore: 0.9), (item: "near", diffScore: 0.1), (item: "mid", diffScore: 0.5)])
        #expect(sorted == ["near", "mid", "far"])
    }

    @Test func relevanceSortKeepsInputOrderForEqualScores() {
        let items = (0 ..< 40).map { (item: $0, diffScore: $0 % 2 == 0 ? 0.5 : 0.25) }
        let sorted = SearchRanker.sortedByRelevance(items)
        #expect(sorted == Array(stride(from: 1, to: 40, by: 2)) + Array(stride(from: 0, to: 40, by: 2)))
    }

    @Test func relevanceSortOfNothingIsEmpty() {
        #expect(SearchRanker.sortedByRelevance([(item: Int, diffScore: Double)]()).isEmpty)
    }

    @Test func titleMatchBeatsKeywordMatchBeatsDescriptionMatch() throws {
        let title = try #require(SearchRanker.diffScore(query: "dock", title: "Show in Dock", keywords: [], description: nil))
        let keyword = try #require(SearchRanker.diffScore(query: "dock", title: "Other", keywords: ["dock"], description: nil))
        let description = try #require(SearchRanker.diffScore(query: "dock", title: "Other", keywords: [], description: "dock"))
        #expect(title < keyword)
        #expect(keyword < description)
    }

    @Test func weakestTitleMatchStillBeatsTheBestKeywordMatch() throws {
        let inside = try #require(SearchRanker.diffScore(query: "ock", title: "Show in Dock", keywords: [], description: nil))
        let exactKeyword = try #require(SearchRanker.diffScore(query: "ock", title: "Other", keywords: ["ock"], description: nil))
        #expect(inside < exactKeyword)
    }

    @Test func initialsOfATitleMatch() {
        #expect(SearchRanker.diffScore(query: "lal", title: "Launch at Login", keywords: [], description: nil) != nil)
    }

    @Test func betterMatchInTheSameFieldScoresLower() throws {
        let prefix = try #require(SearchRanker.diffScore(query: "show", title: "Show in Dock", keywords: [], description: nil))
        let word = try #require(SearchRanker.diffScore(query: "dock", title: "Show in Dock", keywords: [], description: nil))
        #expect(prefix < word)
    }

    @Test func bestFieldDecidesTheScore() throws {
        let both = try #require(SearchRanker.diffScore(query: "dock", title: "Dock", keywords: ["dock"], description: "dock"))
        let titleOnly = try #require(SearchRanker.diffScore(query: "dock", title: "Dock", keywords: [], description: nil))
        #expect(both == titleOnly)
    }

    @Test(arguments: [
        ("xyz", "Show in Dock", ["dock"], "Keeps the icon in the Dock."),
        // Letters in order but scattered are not a match in any field.
        ("lgn", "Launch at Login", ["login item"], "Opens Floe when you log in."),
        ("dock", "Other", [String](), nil as String?),
    ])
    func unrelatedQueriesDoNotMatch(query: String, title: String, keywords: [String], description: String?) {
        #expect(SearchRanker.diffScore(query: query, title: title, keywords: keywords, description: description) == nil)
    }

    @Test func eachWordOfAQueryMayMatchADifferentField() throws {
        let score = try #require(SearchRanker.diffScore(query: "raycast folder", title: "Extensions folder", keywords: ["raycast"], description: nil))
        let keyword = try #require(SearchRanker.diffScore(query: "raycast", title: "Extensions folder", keywords: ["raycast"], description: nil))
        // The weakest word decides.
        #expect(score == keyword)
    }

    @Test func everyWordOfAQueryHasToMatch() {
        #expect(SearchRanker.diffScore(query: "raycast xyz", title: "Extensions folder", keywords: ["raycast"], description: nil) == nil)
    }

    @Test func substringScoreIsWhatFuzzyGivesASubstring() {
        #expect(Fuzzy.score("tivi", "Activity Monitor") == SearchRanker.substringScore)
    }
}

struct SearchIndexTests {
    @Test func staticEntryIDsAreUnique() {
        let ids = SearchIndex.staticEntries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyStaticEntryHasATitleAndTheLabelOfItsPane() {
        for entry in SearchIndex.staticEntries {
            #expect(!entry.title.isEmpty)
            switch entry.pane {
            case .general: #expect(entry.paneLabel == .general)
            case .commands: #expect(entry.paneLabel == .commands)
            case .applications: #expect(entry.paneLabel == .applications)
            case .ai: #expect(entry.paneLabel == .ai)
            case .sync: #expect(entry.paneLabel == .sync)
            case .appearance: #expect(entry.paneLabel == .appearance)
            case .quicklinks: #expect(entry.paneLabel == .quicklinks)
            case .snippets: #expect(entry.paneLabel == .snippets)
            case .extensionStore: #expect(entry.paneLabel == .extensionStore)
            case .privacy: #expect(entry.paneLabel == .privacy)
            case .about: #expect(entry.paneLabel == .about)
            case .extensionPage: Issue.record("\(entry.id) is a static entry on an extension's pane")
            }
        }
    }

    @Test(arguments: [SettingsPage.general, .commands, .applications, .ai, .sync, .quicklinks, .snippets, .extensionStore, .appearance, .privacy, .about])
    func everyPaneOfFloeCanBeFoundByName(pane: SettingsPage) {
        #expect(SearchIndex.paneEntries.contains { $0.pane == pane })
    }

    @Test func aboutHasThawsSymbolInTheSearchResults() {
        #expect(SearchPaneLabel.about == SearchPaneLabel(title: "About", symbol: "cube"))
    }

    @Test func entriesForAPaneAreOnlyThatPanes() {
        let general = SearchIndex.entries(for: .general)
        #expect(general.count == SearchIndex.generalEntries.count + 1)
        #expect(general.allSatisfy { $0.pane == .general })
        #expect(SearchIndex.entries(for: .extensionPage("none")).isEmpty)
    }

    @Test func extensionsFollowTheSidebarOrderWithTheirCommandsInManifestOrder() {
        let ids = SearchIndex.extensionEntries(for: SearchFixture.commands).map(\.id)
        #expect(ids == [
            "extension.alpha-notes",
            "command.alpha-notes/new-note",
            "extension.zeta-tools",
            "extension.zeta-tools.preference.apiToken",
            "command.zeta-tools/convert",
            "command.zeta-tools/convert.preference.precision",
            "command.zeta-tools/timer",
        ])
    }

    @Test func extensionEntriesPointAtTheExtensionsPane() throws {
        let entries = SearchIndex.extensionEntries(for: SearchFixture.commands)
        let zeta = entries.filter { $0.id.contains("zeta-tools") }
        #expect(zeta.allSatisfy { $0.pane == .extensionPage("zeta-tools") })
        let label = try #require(zeta.first?.paneLabel)
        #expect(label == SearchPaneLabel(title: "Zeta Tools", icon: "zeta.png", assetsPath: "/tmp/zeta-tools/assets"))
        // An extension without an icon gets the sidebar's fallback.
        let alpha = try #require(entries.first { $0.id == "extension.alpha-notes" })
        #expect(alpha.paneLabel.icon == "icon:Terminal")
        #expect(alpha.paneLabel.symbol == nil)
    }

    @Test func commandsAndTheirPreferencesAnchorToTheCommand() throws {
        let entries = SearchIndex.extensionEntries(for: SearchFixture.commands)
        let command = try #require(entries.first { $0.id == "command.zeta-tools/convert" })
        #expect(command.title == "Convert Units")
        #expect(command.anchor == "zeta-tools/convert")
        let preference = try #require(entries.first { $0.id == "command.zeta-tools/convert.preference.precision" })
        #expect(preference.title == "Decimal Places")
        #expect(preference.section == "Convert Units")
        #expect(preference.anchor == "zeta-tools/convert")
    }

    @Test func extensionPreferencesKeepTheirDescriptionAndStayAtTheTop() throws {
        let entries = SearchIndex.extensionEntries(for: SearchFixture.commands)
        let preference = try #require(entries.first { $0.id == "extension.zeta-tools.preference.apiToken" })
        #expect(preference.title == "API Token")
        #expect(preference.descriptionText == "Token for the Zeta service.")
        #expect(preference.section == "Preferences")
        #expect(preference.anchor == nil)
    }

    @Test func onlyRaycastExtensionsCarryTheRaycastKeyword() throws {
        let entries = SearchIndex.extensionEntries(for: SearchFixture.commands)
        let alpha = try #require(entries.first { $0.id == "extension.alpha-notes" })
        let zeta = try #require(entries.first { $0.id == "extension.zeta-tools" })
        #expect(alpha.keywords.contains("raycast"))
        #expect(!zeta.keywords.contains("raycast"))
    }

    @Test func noCommandsMeansNoExtensionEntries() {
        #expect(SearchIndex.extensionEntries(for: []).isEmpty)
        #expect(SearchIndex.entries(commands: []).count == SearchIndex.staticEntries.count)
    }
}

@MainActor
struct SearchModelTests {
    @Test(arguments: [
        ("open floe", "general.toggleHotkey"),
        ("launch at login", "general.launchAtLogin"),
        ("startup", "general.launchAtLogin"),
        ("dock", "general.showInDock"),
        ("pop to root", "general.popToRootDelay"),
        ("return to root", "general.popToRootDelay"),
        ("menu bar", "commands.menuBarSearchHotkey"),
        ("permissions", "privacy.permissions"),
        ("accessibility", "privacy.accessibility"),
        ("check for updates", "general.checkForUpdates"),
        ("raycast", "commands.includeRaycastExtensions"),
        ("extensions folder", "commands.extensionsFolder"),
        ("bun", "commands.runtime"),
        ("applications", "pane.applications"),
        ("about", "pane.about"),
        ("credits", "pane.about"),
        ("acknowledgements", "pane.about"),
        ("release notes", "pane.about"),
        ("changelog", "pane.about"),
        ("general", "pane.general"),
        ("sync", "pane.sync"),
        ("terminal", "applications.terminalApp"),
        ("api key", "ai.aiKey"),
        ("icloud", "sync.syncsWithICloud"),
        ("export", "sync.transferSettings"),
        ("detailed logging", "about.diagnosticLogging"),
    ])
    func aSettingIsTheFirstResultForItsOwnWords(query: String, id: String) {
        let model = SearchModel()
        model.searchText = query
        #expect(model.displayedGroups.first?.entries.first?.id == id)
    }

    @Test(arguments: ["", "   ", "\n"])
    func anEmptyQueryIsNotASearch(query: String) {
        let model = SearchModel()
        model.searchText = query
        #expect(!model.isSearching)
        #expect(model.displayedGroups.isEmpty)
        #expect(model.resultCount == 0)
    }

    @Test func aQueryWithNoMatchIsStillASearch() {
        let model = SearchModel()
        model.searchText = "qqqqzzzz"
        #expect(model.isSearching)
        #expect(model.displayedGroups.isEmpty)
    }

    @Test func clearingTheQueryEndsTheSearch() {
        let model = SearchModel()
        model.searchText = "dock"
        #expect(model.isSearching)
        #expect(model.resultCount > 0)
        model.searchText = ""
        #expect(!model.isSearching)
        #expect(model.displayedGroups.isEmpty)
    }

    @Test func resultsAreGroupedByPaneWithTheBestMatchingPaneFirst() throws {
        let model = SearchModel()
        model.searchText = "hotkey"
        let panes = model.displayedGroups.map(\.pane)
        #expect(Set(panes).count == panes.count)
        #expect(panes.contains(.general))
        #expect(panes.contains(.applications))
        let general = try #require(model.displayedGroups.first { $0.pane == .general })
        #expect(general.label == .general)
        #expect(general.entries.allSatisfy { $0.pane == .general })
        #expect(model.resultCount == model.displayedGroups.reduce(0) { $0 + $1.entries.count })
    }

    @Test func extensionsAreFoundOnlyOnceTheirCommandsAreSet() throws {
        let model = SearchModel()
        model.searchText = "convert units"
        #expect(model.displayedGroups.isEmpty)
        // Setting the commands refreshes the results of the query already typed.
        model.setEntries(SearchIndex.entries(commands: SearchFixture.commands))
        let group = try #require(model.displayedGroups.first)
        #expect(group.pane == .extensionPage("zeta-tools"))
        #expect(group.label.title == "Zeta Tools")
        #expect(group.entries.first?.id == "command.zeta-tools/convert")
    }

    @Test(arguments: [
        ("zeta", "extension.zeta-tools"),
        ("alpha-notes", "extension.alpha-notes"),
        ("create note", "command.alpha-notes/new-note"),
        ("timer", "command.zeta-tools/timer"),
        ("api token", "extension.zeta-tools.preference.apiToken"),
        ("decimal", "command.zeta-tools/convert.preference.precision"),
    ])
    func extensionsCommandsAndPreferencesAreFoundByTitle(query: String, id: String) {
        let model = SearchModel()
        model.setEntries(SearchIndex.entries(commands: SearchFixture.commands))
        model.searchText = query
        #expect(model.displayedGroups.first?.entries.first?.id == id)
    }

    @Test func removedExtensionsLeaveTheIndex() {
        let model = SearchModel()
        model.setEntries(SearchIndex.entries(commands: SearchFixture.commands))
        model.setEntries(SearchIndex.entries(commands: []))
        model.searchText = "convert units"
        #expect(model.displayedGroups.isEmpty)
    }

    @Test func resultsStopAtTheLimit() {
        let model = SearchModel()
        model.setEntries(SearchIndex.entries(commands: SearchFixture.manyCommands(SearchModel.resultLimit + 20)))
        model.searchText = "widget"
        #expect(model.resultCount == SearchModel.resultLimit)
    }
}

@MainActor
struct SettingsSearchNavigationTests {
    private func commandEntry() throws -> SearchEntry {
        try #require(SearchIndex.extensionEntries(for: SearchFixture.commands).first { $0.id == "command.zeta-tools/timer" })
    }

    @Test func choosingAResultOpensItsPaneAndEndsTheSearch() throws {
        let selection = SettingsSelection()
        let search = SearchModel()
        search.setEntries(SearchIndex.entries(commands: SearchFixture.commands))
        search.searchText = "timer"
        try SettingsSearchNavigation.selectSearchResult(commandEntry(), selection: selection, search: search)
        #expect(selection.page == .extensionPage("zeta-tools"))
        #expect(search.requestedAnchor == "zeta-tools/timer")
        #expect(search.searchText.isEmpty)
        #expect(!search.isSearching)
    }

    @Test func aResultWithoutAnAnchorClearsAnEarlierRequest() throws {
        let selection = SettingsSelection()
        let search = SearchModel()
        search.requestedAnchor = "left-over"
        let entry = try #require(SearchIndex.generalEntries.first)
        SettingsSearchNavigation.selectSearchResult(entry, selection: selection, search: search)
        #expect(selection.page == .general)
        #expect(search.requestedAnchor == nil)
    }

    @Test(arguments: [
        ("applications.browserApp", SettingsPage.applications),
        ("ai.aiSource", .ai),
        ("sync.syncsWithICloud", .sync),
        ("sync.transferSettings", .sync),
        ("about.diagnosticLogging", .about),
    ])
    func aSettingMovedOutOfGeneralOpensItsNewPage(id: String, page: SettingsPage) throws {
        let selection = SettingsSelection()
        let search = SearchModel()
        let entry = try #require(SearchIndex.staticEntries.first { $0.id == id })
        SettingsSearchNavigation.selectSearchResult(entry, selection: selection, search: search)
        #expect(selection.page == page)
        #expect(SearchIndex.entries(for: .general).allSatisfy { $0.section == "Floe" || $0.section == nil }, "General keeps only Floe's own section")
    }

    @Test func aSidebarJumpEndsTheSearchAndDropsThePendingScroll() {
        let selection = SettingsSelection()
        let search = SearchModel()
        search.searchText = "dock"
        search.requestedAnchor = "zeta-tools/timer"
        SettingsSearchNavigation.selectSidebarPane(.about, selection: selection, search: search)
        #expect(selection.page == .about)
        #expect(search.searchText.isEmpty)
        #expect(search.requestedAnchor == nil)
    }

    @Test func choosingTheCurrentPaneInTheSidebarOnlyEndsTheSearch() {
        let selection = SettingsSelection()
        let search = SearchModel()
        search.searchText = "dock"
        SettingsSearchNavigation.selectSidebarPane(.general, selection: selection, search: search)
        #expect(selection.page == .general)
        #expect(!search.isSearching)
    }

    @Test func anAnchorIsHandedOutOnce() {
        let search = SearchModel()
        #expect(SettingsSearchNavigation.consumeAnchor(search: search) == nil)
        search.requestedAnchor = "zeta-tools/timer"
        #expect(SettingsSearchNavigation.consumeAnchor(search: search) == "zeta-tools/timer")
        #expect(SettingsSearchNavigation.consumeAnchor(search: search) == nil)
    }
}
