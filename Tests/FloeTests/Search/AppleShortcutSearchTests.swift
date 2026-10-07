//
//  AppleShortcutSearchTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// A scanner that finds nothing, so opening the panel reads none of this Mac's folders.
private actor EmptyScanner: CatalogScanning {
    func scanApps() async -> [AppEntry] {
        []
    }

    func scanCommands(includeRaycast _: Bool) async -> [ExtensionCommand] {
        []
    }
}

@MainActor
struct AppleShortcutSearchTests {
    private let scratch: ScratchDefaults
    private let mail = ShortcutSample.mail
    private let focus = ShortcutSample.focus
    private let resize = ShortcutSample.resize

    init() throws {
        scratch = try ScratchDefaults()
    }

    private func context(_ query: String, shortcuts: [AppleShortcut] = ShortcutSample.all, _ configure: (inout SearchContext) -> Void = { _ in }) -> SearchContext {
        var context = SearchContext(query: query)
        context.shortcuts = shortcuts
        configure(&context)
        return context
    }

    private func ids(_ results: [RootResult]) -> [String] {
        results.map(\.id)
    }

    /// A model on scratch settings whose Shortcuts tool is the fake.
    private func makeModel(_ fake: FakeShortcutsTool, isOn: Bool = true, apps: [AppEntry] = []) -> LauncherModel {
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        settings.searchSources = isOn ? [SearchSourceInfo.shortcuts.id] : []
        let snapshot = CatalogSnapshot(apps: apps, commands: [])
        let model = LauncherModel(scanner: EmptyScanner(), settings: settings, usage: UsageStore(defaults: scratch.defaults), snapshot: snapshot, sources: [])
        model.shortcutLibrary.tool = fake.tool
        return model
    }

    /// A model that is switched on and has read the sample list.
    private func loadedModel(_ fake: FakeShortcutsTool = FakeShortcutsTool(list: ShortcutSample.listing), apps: [AppEntry] = []) async -> LauncherModel {
        let model = makeModel(fake, apps: apps)
        await model.reloadShortcuts()?.value
        return model
    }

    // MARK: The row

    @Test func aShortcutsRowIsItsNameWithTheLabelShortcut() {
        let row = RootItem.shortcut(resize)
        #expect(row.title == "Resize Image (Half)")
        #expect(row.subtitle == nil)
        #expect(row.kind == "Shortcut")
        #expect(row.rowLabel == "Shortcut")
        #expect(row.id == "shortcut:\(ShortcutSample.resizeID)")
        #expect(row.settingsKey == row.id, "so a shortcut can be given an alias")
        #expect(row.keywords.isEmpty)
        #expect(!row.isScopeResult && !row.isApp)
        #expect(RootItem.shortcut(AppleShortcut(name: "Renamed", identifier: ShortcutSample.resizeID)).id == row.id, "a rename keeps the favorite and the usage record")
    }

    // MARK: The ordinary search

    @Test func aShortcutIsFoundByItsName() {
        #expect(ids(RootSearch.results(for: context("mail"))).contains(mail.id))
        #expect(ids(RootSearch.results(for: context("resize"))).first == resize.id)
        #expect(!ids(RootSearch.results(for: context("resize"))).contains(mail.id))
    }

    @Test func shortcutsAreNotListedWithoutAQuery() {
        let browsed = RootSearch.results(for: context(""))
        #expect(!browsed.contains { $0.id.hasPrefix("shortcut:") })
        #expect(AppleShortcutSearchProvider().contribution(for: context("")).ranked.isEmpty)
        #expect(AppleShortcutSearchProvider().contribution(for: context("")).searchOnly.count == 3)
    }

    @Test func aFavoriteShortcutIsListedWithoutAQuery() {
        let browsed = RootSearch.results(for: context("") { $0.favorites = [self.focus.id] })
        #expect(browsed.first { $0.id == focus.id }?.section == "Favorites")
        #expect(!ids(browsed).contains(mail.id))
    }

    @Test func aShortcutRanksBesideAnAppWithASimilarName() {
        let app = AppEntry(name: "Mail", url: URL(fileURLWithPath: "/Fake/Applications/Mail.app"))
        let appID = RootItem.app(app).id
        let found = RootSearch.results(for: context("mail") { $0.apps = [app] }).filter { $0.id == mail.id || $0.id == appID }
        #expect(ids(found) == [appID, mail.id], "the whole name is a better match than the start of one")
        let typed = RootSearch.results(for: context("mail me") { $0.apps = [app] })
        #expect(typed.first?.id == mail.id)
        #expect(!ids(typed).contains(appID))
    }

    @Test func aShortcutRanksBesideASystemSettingsPaneWithASimilarName() {
        let pane = SystemSettingsPane(identifier: "com.apple.Keyboard-Settings.extension", title: "Keyboard", symbol: "keyboard", keywords: ["shortcuts"])
        let paneID = RootItem.settingsPane(pane).id
        let found = RootSearch.results(for: context("keyboard") { $0.settingsPanes = [pane] }).filter { $0.id == focus.id || $0.id == paneID }
        #expect(ids(found) == [paneID, focus.id], "the pane's whole name comes before the shortcut that starts with it")
        let used = RootSearch.results(for: context("keyboard") {
            $0.settingsPanes = [pane]
            $0.frecency = { $0 == self.focus.id ? 10 : 0 }
        }).filter { $0.id == focus.id || $0.id == paneID }
        #expect(ids(used) == [focus.id, paneID], "usage counts for a shortcut as it does everywhere")
    }

    @Test func aShortcutAnswersToTheAliasTheUserGaveIt() {
        let found = RootSearch.results(for: context("rs") { $0.aliases = [self.resize.id: "rs"] })
        #expect(found.first?.id == resize.id)
    }

    @Test func withoutShortcutsNothingIsContributed() {
        let contribution = AppleShortcutSearchProvider().contribution(for: context("mail", shortcuts: []))
        #expect(contribution.ranked.isEmpty && contribution.searchOnly.isEmpty && contribution.pinned.isEmpty)
        #expect(contribution.sectioned.isEmpty && contribution.appended.isEmpty)
        #expect(RootSearch.scope(in: context("shortcuts mail", shortcuts: []), scopes: RootSearch.standardScopes()) == nil, "the word is not a scope then")
        #expect(RootSearch.scope(in: context("shortcuts ", shortcuts: []), scopes: RootSearch.standardScopes()) == nil)
    }

    // MARK: The scope

    @Test func theKeywordAndSomeTextShowOnlyTheShortcutsThatMatch() throws {
        let app = AppEntry(name: "Mail", url: URL(fileURLWithPath: "/Fake/Applications/Mail.app"))
        let context = context("shortcuts mail") { $0.apps = [app] }
        let match = try #require(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()))
        #expect(match.scope.keyword == "shortcuts")
        #expect(match.scope.title == "Shortcuts")
        #expect(match.scope.emptyTitle == "No shortcuts match")
        #expect(match.text == "mail")
        let rows = match.rows(match.scope.results(for: match.text, context: context))
        #expect(ids(rows) == [mail.id])
        #expect(rows.allSatisfy { $0.section == "Shortcuts" })
        #expect(match.scope.results(for: "zzz", context: context).isEmpty)
    }

    @Test func theKeywordAndASpaceListEveryShortcutInTheToolsOrder() throws {
        let context = context("Shortcuts ")
        let match = try #require(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()))
        #expect(match.text.isEmpty)
        #expect(match.scope.results(for: match.text, context: context).map(\.id) == ShortcutSample.all.map(\.id))
    }

    @Test func theKeywordAloneIsAnOrdinarySearch() {
        let pane = SystemSettingsPane(identifier: "keyboard", title: "Keyboard", symbol: "keyboard", keywords: ["Keyboard Shortcuts"])
        let app = AppEntry(name: "Shortcuts", url: URL(fileURLWithPath: "/Fake/Applications/Shortcuts.app"))
        let context = context("shortcuts") {
            $0.settingsPanes = [pane]
            $0.apps = [app]
        }
        #expect(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()) == nil)
        #expect(RootSearch.scope(in: self.context("shortcutsfoo bar"), scopes: RootSearch.standardScopes()) == nil)
        let found = ids(RootSearch.results(for: context))
        #expect(found.first == RootItem.app(app).id, "the Shortcuts app is still what the word finds first")
        #expect(found.contains(RootItem.settingsPane(pane).id), "and the pane that has the word among its keywords")
    }

    @Test func aQuicklinkThatAnswersToTheWordKeepsIt() {
        let link = Quicklink(name: "Shortcuts Gallery", keyword: "shortcuts", url: "https://example.com/?q={query}")
        let context = context("shortcuts mail") { $0.quicklinks = [link] }
        #expect(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()) == nil)
    }

    // MARK: In the launcher

    @Test func offMeansNoRowsNoScopeAndNoToolEvenWhenThePanelOpens() {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let model = makeModel(fake, isOn: false)
        #expect(!model.findsShortcuts)
        model.panelWillShow()
        #expect(model.reloadShortcuts() == nil)
        model.query = "mail"
        #expect(!model.results.contains { $0.id.hasPrefix("shortcut:") })
        model.query = "shortcuts "
        #expect(model.activeScope == nil)
        #expect(fake.calls.isEmpty, "the tool was never started")
    }

    @Test func openingThePanelReadsTheListOnceAndTheLauncherFindsAShortcutWithoutListingIt() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let model = makeModel(fake)
        model.panelWillShow()
        await model.reloadShortcuts()?.value
        #expect(fake.calls == [FakeShortcutsTool.listing], "asking again while the list is on its way starts nothing")
        #expect(!model.results.contains { $0.id.hasPrefix("shortcut:") })
        model.query = "resiz"
        #expect(model.results.first?.id == resize.id)
        #expect(model.results.first?.section == nil, "ranked with everything else, not in a section of its own")
    }

    @Test func theSearchShowsTheListItHasWhileTheNextOneIsRead() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing, isGated: true)
        let model = makeModel(fake)
        fake.open()
        await model.reloadShortcuts()?.value
        fake.list("Brand New (\(ShortcutSample.mailID))\n")

        let loading = model.reloadShortcuts()
        model.query = "mail"
        #expect(ids(model.results).contains(mail.id), "the search did not wait for the tool")
        model.query = "brand"
        #expect(!model.results.contains { $0.id.hasPrefix("shortcut:") })
        fake.open()
        await loading?.value
        #expect(model.results.first?.item.title == "Brand New", "a search that is open shows the new list")
    }

    @Test func switchingOffHidesTheRowsAtOnceAndTheNextOpenForgetsTheList() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let model = await loadedModel(fake)
        model.query = "mail"
        #expect(ids(model.results).contains(mail.id))
        model.settings.searchSources = []
        model.query = "mail m"
        #expect(!model.results.contains { $0.id.hasPrefix("shortcut:") })
        model.panelWillShow()
        #expect(model.shortcutLibrary.shortcuts.isEmpty)
        #expect(fake.calls.count == 1)
    }

    @Test func theScopeShowsInTheLauncherUnderItsTitle() async {
        let model = await loadedModel()
        model.query = "shortcuts "
        #expect(model.activeScope?.scope.keyword == "shortcuts")
        #expect(ids(model.results) == ShortcutSample.all.map(\.id))
        #expect(model.results.allSatisfy { $0.section == "Shortcuts" })
        model.query = "shortcuts key"
        #expect(ids(model.results) == [focus.id])
        model.query = "shortcuts"
        #expect(model.activeScope == nil)
    }

    @Test func aShortcutCanBeAFavoriteAndThenShowsWithoutAQuery() async {
        let model = await loadedModel()
        let row = RootItem.shortcut(mail)
        model.toggleFavorite(row)
        #expect(model.isFavorite(row))
        #expect(model.results.first { $0.id == mail.id }?.section == "Favorites")
    }

    @Test func theActionsMenuOfAShortcutRunsOpensCopiesAndKeepsIt() async {
        let model = await loadedModel()
        let row = RootItem.shortcut(mail)
        #expect(model.primaryActionTitle(for: row) == "Run")
        #expect(model.rootActions(for: row).map { $0?.title ?? "-" } == ["Run", "-", "Open in Shortcuts", "Copy Name", "-", "Add to Favorites", "Hide from Search"])
        #expect(LauncherModel.keepsItsPlace(row))
        model.toggleFavorite(row)
        #expect(model.rootActions(for: row).dropLast().last??.title == "Remove from Favorites")
    }

    @Test func returnOnAShortcutRunsItByIdentifierHidesThePanelAndCountsAsAUse() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let model = await loadedModel(fake)
        var hides = 0
        var lines: [String] = []
        model.hidePanel = { hides += 1 }
        model.showHUD = { lines.append($0) }
        model.query = "resize"
        let row = model.results.first { $0.id == resize.id }?.item
        if let row {
            model.activate(row)
        }
        #expect(hides == 1)
        #expect(model.query.isEmpty, "the launcher is back at its root")
        #expect(model.usage.frecency(of: resize.id) > 0)
        let run = await fake.started.first { @Sendable call in call.first == "run" }
        #expect(run == ["run", ShortcutSample.resizeID], "the identifier, and no text from the search")
        #expect(lines.isEmpty)
    }

    @Test func aRunThatFailsShowsTheToolsLastLineInTheHUD() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        fake.answer("run", with: ShortcutsToolResult(succeeded: false, errorOutput: "Running\nError: The action could not run.\n"))
        let model = await loadedModel(fake)
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)
        model.showHUD = { continuation.yield($0) }
        model.activate(.shortcut(mail))
        #expect(await lines.first { @Sendable _ in true } == "Mail Me the Notes failed: Error: The action could not run.")
    }

    @Test func openInShortcutsHandsTheNameToTheToolAndHidesThePanel() async throws {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let model = await loadedModel(fake)
        var hides = 0
        model.hidePanel = { hides += 1 }
        let action = try #require(model.rootActions(for: .shortcut(resize)).compactMap(\.self).first { $0.title == "Open in Shortcuts" })
        action.run()
        #expect(hides == 1)
        #expect(await fake.started.first { @Sendable call in call.first == "view" } == ["view", "--", "Resize Image (Half)"])
        #expect(!fake.calls.contains { $0.first == "run" }, "looking at a shortcut does not run it")
    }

    // MARK: The switch

    @Test func theSwitchIsOffUntilItIsTurnedOnAndComesBackAfterASave() {
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(!settings.searchSources.contains("shortcuts"))
        settings.searchSources.insert(SearchSourceInfo.shortcuts.id)
        settings.save()
        #expect(AppSettings(defaults: scratch.defaults).searchSources == ["shortcuts"])
    }

    @Test func settingsStoredBeforeTheSwitchLoadUnchangedAndLeaveItOff() {
        let older = #"{"commandHotkeys":{},"aliases":{"a/b":"x"},"favorites":["settings"],"searchSources":["tabs"]}"#
        scratch.defaults.set(Data(older.utf8), forKey: "settings")
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(settings.searchSources == ["tabs"])
        #expect(settings.aliases == ["a/b": "x"])
        #expect(settings.favorites == ["settings"])
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let model = LauncherModel(scanner: EmptyScanner(), settings: settings, usage: UsageStore(defaults: scratch.defaults), snapshot: CatalogSnapshot(apps: [], commands: []), sources: [])
        model.shortcutLibrary.tool = fake.tool
        #expect(!model.findsShortcuts)
        #expect(model.reloadShortcuts() == nil)
        #expect(fake.calls.isEmpty)
    }

    @Test func thePrivacyPageListsTheSwitchAfterTheSourcesAndSaysWhatItDoes() {
        #expect(SearchSourceInfo.switches.map(\.id) == ["files", "tabs", "shortcuts"])
        #expect(SearchSourceInfo.all.map(\.id) == ["files", "tabs"], "it is not a source with a section of its own")
        #expect(SearchSourceInfo.shortcuts.title == "Apple Shortcuts")
        let detail = SearchSourceInfo.shortcuts.detail
        #expect(detail.hasPrefix("Finds the shortcuts you made in the Shortcuts app by name and runs the one you pick."))
        #expect(detail.contains("stays on this Mac"))
        #expect(detail.contains("Type “shortcuts” and a space"))
        #expect(!detail.contains("\u{2014}") && !detail.contains("\u{2013}"))
    }

    @Test(arguments: ["apple shortcuts", "shortcuts app"])
    func theSettingsSearchFindsTheSwitch(query: String) {
        let model = SearchModel()
        model.searchText = query
        #expect(model.displayedGroups.first?.entries.first?.id == "privacy.searchSources.shortcuts")
    }
}
