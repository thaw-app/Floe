//
//  SearchScopeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import ApplicationServices
@testable import Floe
import Foundation
import Testing

/// A scope whose later rows arrive only when the test sends them.
private final class SlowScope: SearchScope {
    let keyword: String
    let title = "Slow"
    let emptyTitle = "Nothing slow"
    var immediate: [RootItem] = []
    /// The texts searched for, in order.
    private(set) var started: [String] = []
    private var continuations: [String: AsyncStream<[RootItem]>.Continuation] = [:]

    init(keyword: String = "slow") {
        self.keyword = keyword
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

/// Counts scans from any thread.
private final nonisolated class ScanCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private func file(_ name: String) -> FileResult {
    // No such folder, so opening one in a test opens nothing.
    FileResult(url: URL(fileURLWithPath: "/floe-tests-no-such-folder/\(name)"), name: name, displayPath: "/floe-tests-no-such-folder", contentType: nil, lastUsed: nil)
}

private func clip(_ text: String, pinned: Bool = false, age: TimeInterval = 0, app: String? = nil) -> ClipboardEntry {
    ClipboardEntry(id: UUID(), kind: .text, text: text, date: Date(timeIntervalSince1970: 1_000_000 - age), pinned: pinned, sourceApp: app)
}

private nonisolated func extra(_ name: String, owner: String = "") -> MenuBarExtra {
    MenuBarExtra(id: "test|\(name)", name: name, ownerName: owner, ownerURL: nil, frame: .zero, element: AXUIElementCreateSystemWide())
}

@MainActor
struct SearchScopeTests {
    private let files = SlowScope(keyword: "files")
    private let github = Quicklink(name: "GitHub", keyword: "gh", url: "https://github.com/search?q={query}")

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func makeModel(scopes: [any SearchScope], apps: [AppEntry] = [], usage: UsageStore = .shared) -> LauncherModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "floe-scope-tests-\(UUID().uuidString)")!)
        return LauncherModel(settings: settings, usage: usage, snapshot: CatalogSnapshot(apps: apps, commands: []), scopes: scopes)
    }

    private func scope(_ query: String, _ configure: (inout SearchContext) -> Void = { _ in }) -> ScopeMatch? {
        var context = SearchContext(query: query)
        configure(&context)
        return RootSearch.scope(in: context, scopes: [files, SlowScope(keyword: "menu")])
    }

    // MARK: Parsing

    @Test func aKeywordASpaceAndSomeTextNameAScope() {
        let match = scope("files invoice 2026")
        #expect(match?.scope.keyword == "files")
        #expect(match?.text == "invoice 2026")
        #expect(scope("menu wifi")?.scope.keyword == "menu")
        #expect(scope("  files   invoice  ")?.text == "invoice", "the space around the text is not part of it")
    }

    @Test func theKeywordAloneIsAnOrdinarySearch() {
        #expect(scope("files") == nil)
        #expect(scope("files ") == nil, "a space with nothing after it asks for nothing yet")
        #expect(scope("") == nil)
    }

    @Test func theKeywordInsideOrdinaryTextIsAnOrdinarySearch() {
        #expect(scope("my files invoice") == nil)
        #expect(scope("filesystem check") == nil)
        #expect(scope("file invoice") == nil)
    }

    @Test func theKeywordMatchesInAnyCase() {
        #expect(scope("FILES Invoice")?.text == "Invoice")
        #expect(scope("Menu wifi")?.scope.keyword == "menu")
    }

    @Test func anUnknownKeywordIsAnOrdinarySearch() {
        #expect(scope("photos beach") == nil)
        #expect(scope("gh floe") == nil)
    }

    @Test func aQuicklinkOrAScriptThatAnswersToTheWordKeepsIt() {
        let link = Quicklink(name: "File Server", keyword: "files", url: "https://example.com/?q={query}")
        #expect(scope("files invoice") { $0.quicklinks = [link] } == nil)
        #expect(scope("files invoice") { $0.quicklinks = [github] } != nil, "another keyword takes nothing away")
        let script = ScriptCommand(
            file: URL(fileURLWithPath: "/tmp/menu.sh"), title: "Menu", packageName: nil, mode: .silent,
            needsConfirmation: false, icon: nil, arguments: []
        )
        #expect(scope("menu wifi") { $0.scripts = [script] } == nil)
    }

    // MARK: In the root search

    @Test func aScopeShowsOnlyItsOwnRowsUnderItsTitle() {
        files.immediate = [.file(file("invoice.pdf"))]
        let model = makeModel(scopes: [files], apps: [AppEntry(name: "Invoices", url: URL(fileURLWithPath: "/Applications/Invoices.app"))])
        model.query = "files invoice"
        #expect(model.results.map(\.id) == ["file:/floe-tests-no-such-folder/invoice.pdf"])
        #expect(model.results.map(\.section) == ["Slow"])
        #expect(model.activeScope?.text == "invoice")
        #expect(model.panelState.isCollapsed(in: .compact) == false, "a scope has a query, so the compact panel is open")
    }

    @Test func anAppNamedLikeAScopeIsStillFoundByItsName() {
        let app = AppEntry(name: "Files", url: URL(fileURLWithPath: "/Applications/Files.app"))
        let model = makeModel(scopes: [files], apps: [app])
        model.query = "files"
        #expect(model.results.first?.id == "app:/Applications/Files.app")
        // With a space and nothing after it the search is still the ordinary one.
        for query in ["files", "files "] {
            model.query = query
            #expect(model.results.last?.id == "files-for:\(query)")
            #expect(model.activeScope == nil)
        }
        #expect(files.started.isEmpty, "the scope was never asked")
    }

    @Test func leavingAScopeBringsTheOrdinarySearchBack() {
        let model = makeModel(scopes: [files], apps: [AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))])
        model.query = "files invoice"
        #expect(model.isAwaitingResults)
        model.query = "saf"
        #expect(model.results.first?.id == "app:/Applications/Safari.app")
        #expect(model.activeScope == nil)
        #expect(model.isAwaitingResults == false)
        model.query = ""
        #expect(model.results.contains { $0.section == "Applications" })
    }

    // MARK: Rows that arrive later

    @Test func laterRowsArriveInBatchesThatReplaceTheOnesShown() async {
        let model = makeModel(scopes: [files])
        model.query = "files inv"
        #expect(model.results.isEmpty)
        #expect(model.isAwaitingResults, "the stream is still open")

        files.send([.file(file("invoice.pdf"))], for: "inv")
        await waitFor("the first batch") { model.results.count == 1 }
        #expect(model.isAwaitingResults)

        files.send([.file(file("invoice.pdf")), .file(file("inventory.txt"))], for: "inv")
        await waitFor("the second batch") { model.results.count == 2 }
        #expect(model.results.map(\.item.title) == ["invoice.pdf", "inventory.txt"])
        #expect(model.results.allSatisfy { $0.section == "Slow" })

        files.finish("inv")
        await waitFor("the end of the stream") { !model.isAwaitingResults }
        #expect(model.results.count == 2, "the rows stay once the search is done")
    }

    @Test func rowsForASupersededQueryAreDropped() async {
        let model = makeModel(scopes: [files])
        model.query = "files inv"
        // Sent and superseded in one turn of the main actor: the batch is in flight when the query changes.
        files.send([.file(file("stale-in-flight.pdf"))], for: "inv")
        model.query = "files invoice"
        #expect(files.started == ["inv", "invoice"])

        files.send([.file(file("stale.pdf"))], for: "inv")
        files.send([.file(file("fresh.pdf"))], for: "invoice")
        await waitFor("the fresh batch") { !model.results.isEmpty }
        #expect(model.results.map(\.item.title) == ["fresh.pdf"])

        files.finish("inv")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(model.isAwaitingResults, "the old search ending does not end the new one")
        #expect(model.results.map(\.item.title) == ["fresh.pdf"])
    }

    @Test func rowsThatArriveAfterTheScopeWasLeftAreDropped() async {
        let model = makeModel(scopes: [files])
        model.query = "files inv"
        files.send([.file(file("late.pdf"))], for: "inv")
        model.query = "inv"
        let ordinary = model.results.map(\.id)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(model.results.map(\.id) == ordinary)
        #expect(!ordinary.contains("file:/floe-tests-no-such-folder/late.pdf"))
    }

    @Test func aRefreshThatIsNotANewQueryLeavesARunningScopeAlone() async {
        let model = makeModel(scopes: [files])
        model.query = "files inv"
        files.send([.file(file("invoice.pdf"))], for: "inv")
        await waitFor("the batch") { model.results.count == 1 }

        model.toggleFavorite(.settings)
        model.query = "files inv "
        #expect(files.started == ["inv"], "the search was not started again")
        #expect(model.results.count == 1)
    }

    @Test func aSelectionTheUserMovedStaysOnItsRowWhenABatchArrives() async {
        let model = makeModel(scopes: [files])
        model.query = "files inv"
        files.send([.file(file("a.pdf")), .file(file("b.pdf"))], for: "inv")
        await waitFor("the first batch") { model.results.count == 2 }
        model.selection = 1

        files.send([.file(file("new.pdf")), .file(file("a.pdf")), .file(file("b.pdf"))], for: "inv")
        await waitFor("the second batch") { model.results.count == 3 }
        #expect(model.selectedRootItem?.title == "b.pdf")

        files.send([.file(file("new.pdf"))], for: "inv")
        await waitFor("the third batch") { model.results.count == 1 }
        #expect(model.selection == 0, "a row that is gone leaves the selection inside the list")
    }

    @Test func updatesForAnOlderSearchAreNeverDelivered() async {
        let updates = SearchUpdates()
        var delivered: [String] = []
        var finished = 0
        let old = AsyncStream.makeStream(of: [RootItem].self)
        let new = AsyncStream.makeStream(of: [RootItem].self)
        #expect(updates.follow(old.stream) { delivered += $0.map(\.title) } finish: { finished += 1 })
        old.continuation.yield([.file(file("old.pdf"))])
        #expect(updates.follow(new.stream) { delivered += $0.map(\.title) } finish: { finished += 1 })
        old.continuation.yield([.file(file("older.pdf"))])
        old.continuation.finish()
        new.continuation.yield([.file(file("new.pdf"))])
        new.continuation.finish()
        await waitFor("the newest search to finish") { finished == 1 }
        #expect(delivered == ["new.pdf"])
        #expect(updates.follow(nil) { _ in } finish: {} == false, "a search with nothing more to come is not waited for")
    }

    // MARK: Each scope

    @Test func theClipboardScopeListsMatchingEntriesPinsFirstThenNewest() {
        let entries = [
            clip("meeting notes", age: 30),
            clip("lunch order", age: 20),
            clip("Meeting agenda", pinned: true, age: 90),
            clip("link", age: 10, app: "Meeting Bar"),
        ]
        let scope = ClipboardSearchScope { entries }
        let rows = scope.results(for: "meeting", context: SearchContext(query: "clipboard meeting"))
        #expect(rows.map(\.title) == ["Meeting agenda", "link", "meeting notes"])
        #expect(rows.map(\.rowLabel) == ["Text", "Meeting Bar", "Text"])
        #expect(scope.results(for: "meeting notes", context: SearchContext(query: "")).map(\.title) == ["meeting notes"], "every word has to match")
        #expect(scope.keyword == "clipboard")
        #expect(scope.updates(for: "meeting", context: SearchContext(query: "")) == nil, "the history is already in memory")
    }

    @Test func theClipboardScopeStopsAtItsLimit() {
        let entries = (0 ..< ClipboardSearchScope.limit + 10).map { clip("copy \($0)", age: TimeInterval($0)) }
        let scope = ClipboardSearchScope { entries }
        #expect(scope.results(for: "copy", context: SearchContext(query: "")).count == ClipboardSearchScope.limit)
    }

    @Test func withoutAccessibilityTheMenuScopeIsOneRowThatSaysSo() {
        let scans = ScanCount()
        let scope = MenuBarSearchScope(isTrusted: { false }, scan: {
            scans.increment()
            return []
        })
        let context = SearchContext(query: "menu wifi")
        let rows = scope.results(for: "wifi", context: context)
        #expect(rows.map(\.id) == ["menubar-access"])
        #expect(rows.first?.title == "Floe needs Accessibility to list your menu bar items")
        #expect(scope.updates(for: "wifi", context: context) == nil)
        #expect(scans.value == 0, "nothing is scanned without the permission")
    }

    @Test func theMenuScopeScansOnceAndRanksItemsByTheNameTheyAreShownBy() async {
        let scans = ScanCount()
        let scope = MenuBarSearchScope(isTrusted: { true }, scan: {
            scans.increment()
            return [extra("Clock"), extra("AirPort", owner: "Control Center"), extra("Battery")]
        })
        var context = SearchContext(query: "menu wifi")
        context.menuBarItemNames = ["test|AirPort": "Wifi"]
        #expect(scope.results(for: "wifi", context: context).isEmpty, "nothing is known before the first scan")

        var batches: [[RootItem]] = []
        if let updates = scope.updates(for: "wifi", context: context) {
            for await batch in updates {
                batches.append(batch)
            }
        }
        #expect(batches.map { $0.map(\.title) } == [["Wifi"]])
        #expect(batches.first?.first?.id == "menubar-item:test|AirPort")
        #expect(batches.first?.first?.rowLabel == "Control Center")

        #expect(scope.updates(for: "clock", context: context) == nil, "a fresh scan is reused while typing")
        #expect(scope.results(for: "clock", context: context).map(\.title) == ["Clock"])
        #expect(scans.value == 1)
    }

    @Test func theStandardScopesAreFilesClipboardMenuSSHProcessesPortsAndShortcuts() {
        #expect(RootSearch.standardScopes().map(\.keyword) == ["files", "clipboard", "menu", "ssh", "kill", "port", "receipts", "shortcuts"])
        #expect(RootSearch.standardScopes().map(\.title) == ["Files", "Clipboard History", "Menu Bar Items", "SSH Hosts", "Running Processes", "Listening on the Port", "Receipts", "Shortcuts"])
    }

    // MARK: The new rows

    private var scopeRows: [RootItem] {
        [.file(file("invoice.pdf")), .clipboardEntry(clip("meeting notes")), .menuBarItem(extra("Clock"), name: "Clock"), .menuBarAccess]
    }

    @Test func aScopeRowOpensAsItsOwnViewWouldAndIsNotRecordedAsUsed() throws {
        let usage = try UsageStore(defaults: #require(UserDefaults(suiteName: "floe-scope-usage-\(UUID().uuidString)")))
        let model = makeModel(scopes: [], usage: usage)
        var opened: [String] = []
        model.scopeResultOpener = { opened.append($0.id) }
        let rows = scopeRows
        for row in rows {
            model.activate(row)
        }
        #expect(opened == rows.map(\.id))
        #expect(usage.records.isEmpty, "a row found just now leaves no usage record under its id")

        model.activate(.settings)
        #expect(usage.records.keys.sorted() == ["settings"], "an ordinary row is still recorded")
    }

    @Test func openingAFileRowClosesThePanelAndGoesBackToTheRoot() {
        let model = makeModel(scopes: [files])
        var hidden = 0
        model.hidePanel = { hidden += 1 }
        files.immediate = [.file(file("invoice.pdf"))]
        model.query = "files invoice"
        model.activate(model.results[0].item)
        #expect(hidden == 1)
        #expect(model.query.isEmpty)
        #expect(model.activeScope == nil)
    }

    @Test func scopeRowsCannotBeFavorites() {
        let model = makeModel(scopes: [])
        for row in scopeRows {
            #expect(LauncherModel.keepsItsPlace(row) == false)
            model.toggleFavorite(row)
            #expect(model.isFavorite(row) == false)
            #expect(!model.rootActions(for: row).contains { $0?.title == "Add to Favorites" })
        }
        #expect(RootItem.settings.isScopeResult == false)
    }

    @Test func scopeRowsNameWhatReturnDoesAndAFileOffersItsFileActions() {
        let model = makeModel(scopes: [])
        let rows = scopeRows
        #expect(rows.map(model.primaryActionTitle) == ["Open", "Paste", "Click Item", "Open"])
        let fileTitles = model.rootActions(for: rows[0]).map { $0?.title ?? "-" }
        #expect(fileTitles.first == "Open")
        #expect(fileTitles.contains("Show in Finder") && fileTitles.contains("Copy Path"))
        #expect(model.rootActions(for: rows[1]).map { $0?.title ?? "-" } == ["Paste", "Copy"])
        #expect(model.rootActions(for: rows[2]).map { $0?.title ?? "-" } == ["Click Item"])
    }

    @Test func scopeRowsHaveNoAliasAndSayWhatKindTheyAre() {
        #expect(scopeRows.map(\.kind) == ["File", "Clipboard", "Menu Bar", "Menu Bar"])
        #expect(scopeRows.allSatisfy { $0.settingsKey == nil })
        #expect(scopeRows[0].rowLabel == "floe-tests-no-such-folder")
        #expect(RootItem.settings.rowLabel == "Floe", "an ordinary row still shows its kind")
    }
}
