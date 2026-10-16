//
//  SearchSourceTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// A source whose later rows arrive only when the test sends them.
private final class SlowSource: SearchSource {
    let id: String
    let keyword: String
    let title: String
    let emptyTitle = "Nothing slow"
    var immediate: [RootItem] = []
    /// The texts searched for, in order.
    private(set) var started: [String] = []
    private var continuations: [String: AsyncStream<[RootItem]>.Continuation] = [:]

    init(id: String = "slow", title: String = "Slow") {
        self.id = id
        keyword = id
        self.title = title
    }

    func results(for _: String, context _: SearchContext) -> [RootItem] {
        immediate
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        started.append(text)
        let (stream, continuation) = AsyncStream.makeStream(of: [RootItem].self)
        continuations[text] = continuation
        return stream
    }

    func send(_ rows: [RootItem], for text: String) {
        continuations[text]?.yield(rows)
    }

    func finish(_ text: String) {
        continuations[text]?.finish()
    }
}

private func file(_ name: String) -> RootItem {
    // No such folder, so opening one in a test opens nothing.
    .file(FileResult(url: URL(fileURLWithPath: "/floe-tests-no-such-folder/\(name)"), name: name, displayPath: "/floe-tests-no-such-folder", contentType: nil, lastUsed: nil))
}

private func app(_ name: String) -> AppEntry {
    AppEntry(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
}

@MainActor
struct SearchSourceTests {
    private let slow = SlowSource()
    private let settings = AppSettings(defaults: MemoryDefaults())

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func makeModel(sources: [any SearchSource]? = nil, on: Set<String> = ["slow"], apps: [AppEntry] = []) -> LauncherModel {
        settings.searchSources = on
        return LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: apps, commands: []), scopes: [], sources: sources ?? [slow])
    }

    private func sourceRows(_ model: LauncherModel, _ section: String = "Slow") -> [String] {
        model.results.filter { $0.section == section }.map(\.item.title)
    }

    // MARK: In an ordinary search

    @Test func aSourceThatIsSwitchedOffAddsNothingAndIsNeverAsked() async {
        slow.immediate = [file("invoice.pdf")]
        let model = makeModel(on: [])
        model.query = "invoice"
        try? await Task.sleep(for: .milliseconds(20))
        #expect(slow.started.isEmpty)
        #expect(sourceRows(model).isEmpty)
        #expect(model.isAwaitingResults == false)
    }

    @Test func anEnabledSourceAddsAtMostThreeRowsInItsSectionBetweenTheRankedAndTheAppendedRows() async throws {
        let model = makeModel(apps: [app("Invoices")])
        model.query = "invoice"
        slow.send((1 ... 5).map { file("invoice-\($0).pdf") }, for: "invoice")
        await waitFor("the source's rows") { !sourceRows(model).isEmpty }

        #expect(sourceRows(model) == ["invoice-1.pdf", "invoice-2.pdf", "invoice-3.pdf"])
        #expect(SourceSearch.rowLimit == 3)
        let ids = model.results.map(\.id)
        let ranked = try #require(ids.firstIndex(of: "app:/Applications/Invoices.app"))
        let first = try #require(ids.firstIndex(of: "file:/floe-tests-no-such-folder/invoice-1.pdf"))
        let appended = try #require(ids.firstIndex(of: "files-for:invoice"))
        #expect(ranked == 0)
        #expect(ranked < first && first + 2 < appended)
        #expect(model.results[..<first].allSatisfy { $0.section == nil }, "every ranked row is above the section")
    }

    @Test func rowsKnownAtOnceAreShownWithTheRankedRowsAndCutToThree() {
        slow.immediate = (1 ... 4).map { file("known-\($0).txt") }
        let model = makeModel()
        model.query = "known"
        #expect(sourceRows(model) == ["known-1.txt", "known-2.txt", "known-3.txt"])
    }

    @Test func rankedRowsAreThereBeforeASlowSourceAnswersAndKeepTheirOrderWhenItDoes() async {
        let model = makeModel(apps: [app("Safari"), app("Safari Technology Preview"), app("Safe Notes")])
        model.query = "saf"
        let before = model.results.map(\.id)
        #expect(before.first == "app:/Applications/Safari.app")
        #expect(Set(before.prefix(3)) == ["app:/Applications/Safari.app", "app:/Applications/Safari Technology Preview.app", "app:/Applications/Safe Notes.app"])
        #expect(sourceRows(model).isEmpty, "the source has not answered")
        #expect(model.isAwaitingResults)

        slow.send([file("safe.txt")], for: "saf")
        await waitFor("the source's row") { sourceRows(model) == ["safe.txt"] }
        #expect(model.results.map(\.id).filter { $0 != "file:/floe-tests-no-such-folder/safe.txt" } == before, "nothing else moved")
        #expect(model.selection == 0)

        slow.finish("saf")
        await waitFor("the end of the search") { !model.isAwaitingResults }
        #expect(sourceRows(model) == ["safe.txt"], "the rows stay once the source is done")
    }

    @Test func aSourcesRowsForASupersededQueryAreDropped() async {
        let model = makeModel()
        model.query = "inv"
        // Sent and superseded in one turn of the main actor: the batch is in flight when the query changes.
        slow.send([file("stale-in-flight.pdf")], for: "inv")
        model.query = "invoice"
        #expect(slow.started == ["inv", "invoice"])
        #expect(sourceRows(model).isEmpty, "the old query's rows are gone at once")

        slow.send([file("stale.pdf")], for: "inv")
        slow.send([file("fresh.pdf")], for: "invoice")
        await waitFor("the fresh rows") { !sourceRows(model).isEmpty }
        #expect(sourceRows(model) == ["fresh.pdf"])
        try? await Task.sleep(for: .milliseconds(20))
        #expect(sourceRows(model) == ["fresh.pdf"])
    }

    @Test func rowsThatArriveAfterTheQueryWasClearedAreDropped() async {
        let model = makeModel()
        model.query = "invoice"
        slow.send([file("late.pdf")], for: "invoice")
        model.query = ""
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!model.results.contains { $0.id.hasPrefix("file:") })
        #expect(model.isAwaitingResults == false)
    }

    @Test func aQueryUnderThreeCharactersDoesNotRunASource() {
        slow.immediate = [file("in.txt")]
        let model = makeModel()
        for query in ["i", "in", "  in  "] {
            model.query = query
            #expect(sourceRows(model).isEmpty)
        }
        #expect(slow.started.isEmpty)
        model.query = "inv"
        #expect(slow.started == ["inv"])
        #expect(SourceSearch.minimumQueryLength == 3)
    }

    @Test func theSelectedRowDoesNotJumpWhenASourcesRowsArrive() async {
        let model = makeModel(apps: [app("Safari"), app("Safari Technology Preview")])
        model.query = "safari"
        model.selection = 1
        slow.send([file("safari-notes.txt")], for: "safari")
        await waitFor("the source's row") { !sourceRows(model).isEmpty }
        #expect(model.selection == 1)
        #expect(model.selectedRootItem?.id == "app:/Applications/Safari Technology Preview.app")

        // A row below the section moves down with it and stays selected.
        model.selection = model.results.count - 1
        #expect(model.selectedRootItem?.id == "files-for:safari")
        slow.send([file("safari-notes.txt"), file("safari-plan.txt")], for: "safari")
        await waitFor("the second batch") { sourceRows(model).count == 2 }
        #expect(model.selectedRootItem?.id == "files-for:safari")
    }

    @Test func aRefreshThatIsNotANewQueryLeavesARunningSourceAlone() async {
        let model = makeModel()
        model.query = "invoice"
        slow.send([file("invoice.pdf")], for: "invoice")
        await waitFor("the source's row") { !sourceRows(model).isEmpty }

        model.toggleFavorite(.settings)
        model.query = "invoice "
        #expect(slow.started == ["invoice"], "the source was not asked again")
        #expect(sourceRows(model) == ["invoice.pdf"])
    }

    @Test func eachSourceHasItsOwnSectionInTheSourcesOrder() async {
        let other = SlowSource(id: "other", title: "Other")
        let model = makeModel(sources: [slow, other], on: ["slow", "other"])
        model.query = "plan"
        other.send((1 ... 4).map { file("other-\($0).txt") }, for: "plan")
        await waitFor("the second source") { !sourceRows(model, "Other").isEmpty }
        #expect(model.isAwaitingResults, "the first source is still searching")
        slow.send([file("slow-1.txt")], for: "plan")
        await waitFor("the first source") { !sourceRows(model).isEmpty }
        let sections = model.results.compactMap(\.section).filter { $0 == "Slow" || $0 == "Other" }
        #expect(sections == ["Slow", "Other", "Other", "Other"])
    }

    @Test func switchingASourceOffDropsItsRowsOnTheNextSearch() async {
        let model = makeModel()
        model.query = "invoice"
        slow.send([file("invoice.pdf")], for: "invoice")
        await waitFor("the source's row") { !sourceRows(model).isEmpty }
        settings.searchSources = []
        model.query = "invoices"
        #expect(sourceRows(model).isEmpty)
        #expect(slow.started == ["invoice"])
    }

    // MARK: The keyword

    @Test func aSourcesKeywordShowsEveryMatchAndTheKeywordAloneIsAnOrdinarySearch() async {
        let model = makeModel()
        model.query = "slow invoice"
        #expect(model.activeScope?.text == "invoice")
        slow.send((1 ... 5).map { file("invoice-\($0).pdf") }, for: "invoice")
        await waitFor("the scope's rows") { !model.results.isEmpty }
        #expect(model.results.count == 5, "the scope is not cut to three")
        #expect(model.results.allSatisfy { $0.section == "Slow" })

        for query in ["slow", "slow "] {
            model.query = query
            #expect(model.activeScope == nil)
            #expect(model.results.last?.id == "files-for:\(query)")
        }
    }

    @Test func theKeywordOfASourceThatIsSwitchedOffIsAnOrdinarySearch() {
        let model = makeModel(on: [])
        model.query = "slow invoice"
        #expect(model.activeScope == nil)
        #expect(slow.started.isEmpty)
    }

    // MARK: The standard sources

    @Test func theStandardSourcesAreFilesAndTabsAndThePrivacyPageDescribesEach() {
        let sources = RootSearch.standardSources()
        #expect(sources.map(\.id) == ["files", "tabs"])
        #expect(sources.map(\.keyword) == ["files", "tabs"])
        #expect(sources.map(\.title) == ["Files", "Browser Tabs"])
        #expect(SearchSourceInfo.all.map(\.id) == sources.map(\.id))
        #expect(SearchSourceInfo.all.allSatisfy { $0.detail.contains("on this Mac") })
        #expect(SearchSourceInfo.tabs.detail.contains("Safari, Dia, Helium"))
        #expect(SearchSourceInfo.tabs.detail.contains("macOS asks for permission the first time"))
    }

    @Test func onlyTheSourcesThatAreSwitchedOnAreEnabled() {
        let sources: [any SearchSource] = [slow, SlowSource(id: "other", title: "Other")]
        #expect(RootSearch.enabled(sources, in: []).isEmpty)
        #expect(RootSearch.enabled(sources, in: ["other", "unknown"]).map(\.id) == ["other"])
    }

    @Test func aFileRowFromASourceOffersTheFileActionsAndIsNotAFavorite() {
        let model = makeModel()
        let row = file("invoice.pdf")
        let titles = model.rootActions(for: row).map { $0?.title ?? "-" }
        #expect(titles.first == "Open")
        #expect(titles.contains("Show in Finder") && titles.contains("Copy Path"))
        #expect(!titles.contains("Add to Favorites"))
        #expect(LauncherModel.keepsItsPlace(row) == false)
    }

    @Test(arguments: [("search sources", "privacy.searchSources"), ("browser tabs", "privacy.searchSources.tabs"), ("spotlight", "privacy.searchSources.files")])
    func theSettingsSearchFindsTheSources(query: String, id: String) {
        let model = SearchModel()
        model.searchText = query
        #expect(model.displayedGroups.first?.entries.first?.id == id)
    }
}
