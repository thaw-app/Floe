//
//  BrowserTabTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Stands in for running a script: it records what it was asked to run and answers from a table.
/// No test runs a real script, so no browser is ever asked for anything.
private final nonisolated class FakeScripts: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [String] = []
    private let answer: @Sendable (String) -> AppleScriptOutcome

    init(_ answer: @escaping @Sendable (String) -> AppleScriptOutcome) {
        self.answer = answer
    }

    var ran: [String] {
        lock.withLock { sources }
    }

    var run: AppleScriptRunner {
        { [self] source in
            lock.withLock { sources.append(source) }
            return answer(source)
        }
    }
}

/// What a listing script answers: one row per tab, as the script joins them.
private nonisolated func listing(_ rows: [(window: String, key: String, title: String, url: String)]) -> String {
    rows.map { [$0.window, $0.key, $0.title, $0.url].joined(separator: BrowserTabScripts.fieldSeparator) + BrowserTabScripts.rowSeparator }.joined()
}

private func tab(_ title: String, _ url: String, browser: BrowserApp = .safari, window: String = "1", key: String = "1") -> BrowserTab {
    BrowserTab(browser: browser, window: window, key: key, title: title, url: url)
}

@MainActor
struct BrowserTabTests {
    private let safariListing = listing([
        ("101", "1", "Floe: pull requests", "https://github.com/floe/pulls"),
        ("101", "2", "Invoice 2026", "https://billing.example.com/invoices/7"),
        ("205", "1", "", "https://www.example.org/start"),
        ("205", "2", "Weather", ""),
    ])

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func batches(_ stream: AsyncStream<[RootItem]>?) async -> [[String]] {
        var batches: [[String]] = []
        if let stream {
            for await batch in stream {
                batches.append(batch.map(\.title))
            }
        }
        return batches
    }

    // MARK: Reading what a browser answers

    @Test func aListingIsReadIntoTabsAcrossSeveralWindows() {
        let tabs = BrowserTabScripts.parse(safariListing, browser: .safari)
        #expect(tabs.map(\.window) == ["101", "101", "205", "205"])
        #expect(tabs.map(\.key) == ["1", "2", "1", "2"])
        #expect(tabs.map(\.title) == ["Floe: pull requests", "Invoice 2026", "", "Weather"])
        #expect(tabs[1].url == "https://billing.example.com/invoices/7")
        #expect(tabs.allSatisfy { $0.browser == .safari })
    }

    @Test func anEmptyOrBrokenListingHasNoTabs() {
        #expect(BrowserTabScripts.parse("", browser: .safari).isEmpty)
        #expect(BrowserTabScripts.parse("not a listing", browser: .safari).isEmpty)
        let cutShort = "101" + BrowserTabScripts.fieldSeparator + "1" + BrowserTabScripts.rowSeparator
        #expect(BrowserTabScripts.parse(cutShort, browser: .safari).isEmpty)
    }

    @Test func aTabRowShowsItsTitleOrItsAddressAndTheSiteAtTheEdge() {
        let tabs = BrowserTabScripts.parse(safariListing, browser: .safari)
        let rows = tabs.map { RootItem.browserTab(.tab($0)) }
        #expect(rows.map(\.title) == ["Floe: pull requests", "Invoice 2026", "https://www.example.org/start", "Weather"])
        #expect(rows.map(\.rowLabel) == ["github.com", "billing.example.com", "example.org", "Safari"])
        #expect(rows.map(\.id) == [
            "browser-tab:com.apple.Safari|101|1", "browser-tab:com.apple.Safari|101|2",
            "browser-tab:com.apple.Safari|205|1", "browser-tab:com.apple.Safari|205|2",
        ])
        #expect(rows.allSatisfy { $0.kind == "Browser Tab" && $0.settingsKey == nil && $0.isScopeResult })
    }

    // MARK: Matching

    @Test func tabsMatchOnTitleAndAddressWithTitleMatchesFirst() {
        let tabs = [
            tab("Pricing", "https://github.com/pricing", key: "1"),
            tab("GitHub Status", "https://www.githubstatus.com", key: "2"),
            tab("Café menu", "https://example.com/menu", key: "3"),
            tab("Floe issues", "https://github.com/floe/issues", key: "4"),
        ]
        #expect(BrowserTabs.matching(tabs, query: "github").map(\.title) == ["GitHub Status", "Pricing", "Floe issues"])
        #expect(BrowserTabs.matching(tabs, query: "floe github").map(\.title) == ["Floe issues"], "each word may be in the title or the address")
        #expect(BrowserTabs.matching(tabs, query: "CAFE").map(\.title) == ["Café menu"], "case and accents do not matter")
        #expect(BrowserTabs.matching(tabs, query: "nothing").isEmpty)
        #expect(BrowserTabs.matching(tabs, query: "  ").isEmpty)
    }

    // MARK: Asking the browsers

    @Test func everyBrowserInTheTableHasAScriptThatOnlyTalksToItWhileItIsRunning() {
        #expect(BrowserApp.all.map(\.name) == ["Safari", "Dia", "Helium", "Google Chrome", "Brave Browser", "Microsoft Edge", "Vivaldi"])
        for browser in BrowserApp.all {
            let script = BrowserTabScripts.list(browser)
            let app = "application id \"\(browser.bundleID)\""
            let guardLine = script.range(of: "if \(app) is running then")
            let tell = script.range(of: "tell \(app)")
            #expect(guardLine != nil && tell != nil)
            if let guardLine, let tell {
                #expect(guardLine.lowerBound < tell.lowerBound, "the check comes before anything is asked")
            }
            #expect(script.components(separatedBy: "tell application").count == 2, "nothing else is told anything")
            #expect(script.contains("set floeTitles to \(browser.titleTerm) of tabs of floeWindow"))
            #expect(script.contains("set floeAddresses to URL of tabs of floeWindow"))
            #expect(!script.contains("activate") && !script.contains("launch"))
        }
        #expect(BrowserTabScripts.list(.safari).contains("set floeTitles to name of tabs"))
        #expect(BrowserTabScripts.list(.dia).contains("set floeKeys to id of tabs of floeWindow"))
    }

    @Test func readingAsksEachBrowserInTurnAndKeepsTheOnesThatRefusedApart() async {
        let scripts = FakeScripts { source in
            if source.contains("com.apple.Safari") {
                return .text(listing([("1", "1", "Apple", "https://apple.com")]))
            }
            return source.contains("company.thebrowser.dia") ? .refused : .failed
        }
        let snapshot = await BrowserTabs.read(BrowserApp.all, run: scripts.run)
        #expect(snapshot.tabs.map(\.title) == ["Apple"])
        #expect(snapshot.refused == [.dia], "a refusal is remembered; any other failure adds nothing")
        #expect(scripts.ran == BrowserApp.all.map(BrowserTabScripts.list))
    }

    @Test func aBrowserThatIsNotRunningIsNeverAsked() async {
        let scripts = FakeScripts { _ in .text(listing([("1", "1", "Apple", "https://apple.com")])) }
        let source = TabSearchSource(browsers: BrowserApp.all, isRunning: { _ in false }, run: scripts.run)
        let context = SearchContext(query: "apple")
        #expect(await batches(source.inlineUpdates(for: "apple", context: context)) == [[]])
        #expect(scripts.ran.isEmpty, "no script ran, so nothing could have launched a browser")
        #expect(source.results(for: "apple", context: context).isEmpty)
    }

    @Test func theTabListIsReadOnceAndReusedForAFewSeconds() async {
        let scripts = FakeScripts { _ in .text(listing([("1", "1", "Apple", "https://apple.com"), ("1", "2", "Apple Music", "https://music.apple.com")])) }
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let source = TabSearchSource(browsers: [.safari], isRunning: { _ in true }, run: scripts.run, now: { clock })
        let context = SearchContext(query: "")
        #expect(source.inlineResults(for: "app", context: context).isEmpty, "nothing is known before the first read")
        #expect(await batches(source.inlineUpdates(for: "app", context: context)) == [["Apple", "Apple Music"]])

        clock += TabSearchSource.listLifetime - 1
        #expect(source.inlineUpdates(for: "music", context: context) == nil, "a fresh list is reused while typing")
        #expect(source.inlineResults(for: "music", context: context).map(\.title) == ["Apple Music"])
        #expect(scripts.ran.count == 1)

        clock += 2
        #expect(await batches(source.inlineUpdates(for: "apple", context: context)) == [["Apple", "Apple Music"]])
        #expect(scripts.ran.count == 2, "an old list is read again")
    }

    @Test func aRefusalAddsNothingToAnOrdinarySearchAndOneRowToTheScope() async {
        let scripts = FakeScripts { _ in .refused }
        let source = TabSearchSource(browsers: [.safari], isRunning: { _ in true }, run: scripts.run)
        let context = SearchContext(query: "")
        #expect(await batches(source.inlineUpdates(for: "apple", context: context)) == [[]])
        #expect(source.inlineResults(for: "apple", context: context).isEmpty)

        let rows = source.results(for: "apple", context: context)
        #expect(rows.map(\.id) == ["browser-access:com.apple.Safari"])
        #expect(rows.first?.title == "Floe needs permission to list Safari's tabs")
        #expect(rows.first?.rowLabel == "Safari")
    }

    // MARK: In the root search

    private func makeModel(_ source: TabSearchSource, on: Bool = true, usage: UsageStore = .shared) -> LauncherModel {
        let settings = AppSettings(defaults: MemoryDefaults())
        settings.searchSources = on ? ["tabs"] : []
        return LauncherModel(settings: settings, usage: usage, snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [source])
    }

    private var manyTabs: TabSearchSource {
        let rows = (1 ... 5).map { (window: "1", key: "\($0)", title: "Invoice \($0)", url: "https://example.com/\($0)") }
        let scripts = FakeScripts { _ in .text(listing(rows)) }
        return TabSearchSource(browsers: [.safari], isRunning: { _ in true }, run: scripts.run)
    }

    @Test func theTabsScopeShowsEveryMatchAndAnOrdinarySearchThree() async {
        let model = makeModel(manyTabs)
        model.query = "tabs invoice"
        #expect(model.activeScope?.scope.keyword == "tabs")
        await waitFor("the tabs") { !model.results.isEmpty }
        #expect(model.results.map(\.item.title) == (1 ... 5).map { "Invoice \($0)" })
        #expect(model.results.allSatisfy { $0.section == "Browser Tabs" })

        model.query = "invoice"
        #expect(model.activeScope == nil)
        #expect(model.results.filter { $0.section == "Browser Tabs" }.map(\.item.title) == ["Invoice 1", "Invoice 2", "Invoice 3"])
    }

    @Test func theTabsKeywordAloneIsAnOrdinarySearchAndSoIsItWhileTheSourceIsOff() {
        let model = makeModel(manyTabs)
        for query in ["tabs", "tabs "] {
            model.query = query
            #expect(model.activeScope == nil)
        }
        let off = makeModel(manyTabs, on: false)
        off.query = "tabs invoice"
        #expect(off.activeScope == nil)
        #expect(off.isAwaitingResults == false, "no browser is asked while the switch is off")
    }

    // MARK: Switching to a tab

    @Test func switchingToASafariTabSelectsItByItsPlaceAndChecksItsAddress() {
        let script = BrowserTabScripts.activate(tab("Invoice \"7\"", "https://example.com/a\"b", window: "101", key: "3"))
        #expect(script.contains("if application id \"com.apple.Safari\" is running then"))
        #expect(script.contains("tell application id \"com.apple.Safari\""))
        #expect(script.contains("if ((id of floeWindow) as text) is \"101\" then"))
        #expect(script.contains("set floeWanted to \"https://example.com/a\\\"b\""), "a quote in the address cannot end the text")
        #expect(script.contains("set floeValues to URL of tabs of floeWindow"))
        #expect(script.contains("if 3 > 0 and (count of floeValues) >= 3 and my floeText(item 3 of floeValues) is floeWanted then"))
        #expect(script.contains("set current tab of floeWindow to tab floeIndex of floeWindow"))
        #expect(script.contains("set index of floeWindow to 1"))
        #expect(!script.contains("focus tab") && !script.contains("active tab index"))
    }

    @Test func switchingToATabOfAnotherBrowserUsesThatBrowsersOwnTerms() {
        let helium = BrowserTabScripts.activate(tab("Docs", "https://example.com", browser: .helium, window: "77", key: "1234"))
        #expect(helium.contains("tell application id \"net.imput.helium\""))
        #expect(helium.contains("set floeWanted to \"1234\""))
        #expect(helium.contains("set floeValues to id of tabs of floeWindow"))
        #expect(helium.contains("set active tab index of floeWindow to floeIndex"))
        #expect(!helium.contains("Safari") && !helium.contains("current tab"))

        let dia = BrowserTabScripts.activate(tab("Docs", "https://example.com", browser: .dia, window: "A-1", key: "T-9"))
        #expect(dia.contains("tell application id \"company.thebrowser.dia\""))
        #expect(dia.contains("if ((id of floeWindow) as text) is \"A-1\" then"))
        #expect(dia.contains("set floeWanted to \"T-9\""))
        #expect(dia.contains("focus tab floeIndex of floeWindow"))
        for script in [helium, dia] {
            #expect(script.contains("is running then"))
            #expect(script.contains("return \"ok\""))
        }
    }

    @Test func activatingATabHandsItsScriptToTheRunnerAndReportsHowItEnded() async {
        let scripts = FakeScripts { _ in .text(BrowserTabScripts.switched) }
        let wanted = tab("Docs", "https://example.com", browser: .dia, window: "A-1", key: "T-9")
        var outcome: AppleScriptOutcome?
        BrowserTabs.activate(wanted, run: scripts.run) { outcome = $0 }
        await waitFor("the script to end") { outcome != nil }
        #expect(outcome == .text("ok"))
        #expect(scripts.ran == [BrowserTabScripts.activate(wanted)])
    }

    @Test func tabRowsAreOpenedWithoutAUsageRecordAndCannotBeFavorites() {
        let usage = UsageStore(defaults: MemoryDefaults())
        let model = makeModel(manyTabs, usage: usage)
        var opened: [String] = []
        model.scopeResultOpener = { opened.append($0.id) }
        let rows: [RootItem] = [.browserTab(.tab(tab("Docs", "https://example.com"))), .browserTab(.access(.safari))]
        for row in rows {
            model.activate(row)
            #expect(LauncherModel.keepsItsPlace(row) == false)
            model.toggleFavorite(row)
            #expect(model.isFavorite(row) == false)
            #expect(!model.rootActions(for: row).contains { $0?.title == "Add to Favorites" })
        }
        #expect(opened == rows.map(\.id))
        #expect(usage.records.isEmpty)
        #expect(rows.map(model.primaryActionTitle) == ["Switch to Tab", "Open"])
    }
}
