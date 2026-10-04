//
//  TypedLocationSearchProviderTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct TypedLocationSearchProviderTests {
    private let github = Quicklink(name: "GitHub", keyword: "gh", url: "https://github.com/search?q={query}")
    private let google = Quicklink(name: "Google", keyword: "g", url: "https://www.google.com/search?q={query}", isFallback: true)
    private let safari = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))

    /// A disk with one folder and one file on it, and a home that is nobody's.
    private let provider = TypedLocationSearchProvider(
        home: { "/Users/someone" },
        kind: { ["/Users/someone/Downloads": .folder, "/Users/someone": .folder, "/Users/someone/x y.txt": .file][$0] }
    )

    private func context(_ query: String, _ configure: (inout SearchContext) -> Void = { _ in }) -> SearchContext {
        var context = SearchContext(query: query)
        context.apps = [safari]
        context.quicklinks = [github, google]
        context.canAskAI = true
        configure(&context)
        return context
    }

    /// The root search with this provider's disk, and the same search without the provider.
    private func search(_ query: String, _ configure: (inout SearchContext) -> Void = { _ in }) -> (with: [RootResult], without: [RootResult]) {
        let others = RootSearch.providers.filter { !($0 is TypedLocationSearchProvider) }
        let all: [any SearchProvider] = RootSearch.providers.map { $0 is TypedLocationSearchProvider ? provider : $0 }
        let context = context(query, configure)
        return (RootSearch.results(for: context, providers: all), RootSearch.results(for: context, providers: others))
    }

    private func titles(_ results: [RootResult]) -> [String] {
        results.map { "\($0.section ?? "")|\($0.id)|\($0.item.title)" }
    }

    private func makeModel(usage: UsageStore = .shared) -> LauncherModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "floe-typed-location-\(UUID().uuidString)")!)
        let model = LauncherModel(settings: settings, usage: usage, snapshot: CatalogSnapshot(apps: [safari], commands: []), scopes: RootSearch.standardScopes(), sources: [])
        // A Mac with no browser, so no row is named after the one on the Mac running the tests.
        model.appLookup = AppLookup(url: { _ in nil }, plainTextApp: { nil }, exists: { _ in false }, bundleIdentifier: { _ in nil })
        return model
    }

    // MARK: The rows

    @Test func theRootSearchAsksTheProviderOnce() {
        #expect(RootSearch.providers.count { $0 is TypedLocationSearchProvider } == 1)
    }

    @Test func anAddressLeadsWithTheRowThatOpensIt() throws {
        let contribution = provider.contribution(for: context(" github.com/thaw-app "))
        #expect(contribution.ranked.isEmpty && contribution.searchOnly.isEmpty && contribution.sectioned.isEmpty && contribution.appended.isEmpty)
        let row = try #require(contribution.pinned.first)
        #expect(contribution.pinned.count == 1)
        #expect(row.section == nil)
        #expect(row.item.title == "Open github.com/thaw-app")
        #expect(row.item.kind == "Web Address" && row.item.rowLabel == "Web Address")
        #expect(row.item.subtitle == nil && row.item.settingsKey == nil && row.item.keywords.isEmpty)
        guard case let .webAddress(address) = row.item else {
            Issue.record("not an address row")
            return
        }
        #expect(address.url.absoluteString == "https://github.com/thaw-app")
    }

    @Test(arguments: [
        ("~/Downloads", "/Users/someone/Downloads", "Downloads", "someone"),
        ("~/Downloads/", "/Users/someone/Downloads", "Downloads", "someone"),
        ("~", "/Users/someone", "someone", "Users"),
        ("~/Documents/../x y.txt", "/Users/someone/x y.txt", "x y.txt", "someone"),
        ("/Users/someone/x y.txt", "/Users/someone/x y.txt", "x y.txt", "someone"),
    ])
    func aPathLeadsWithTheFileRowForIt(typed: String, path: String, title: String, label: String) throws {
        let contribution = provider.contribution(for: context(typed))
        let row = try #require(contribution.pinned.first)
        #expect(contribution.pinned.count == 1 && contribution.ranked.isEmpty && contribution.appended.isEmpty)
        #expect(row.id == "file:\(path)")
        #expect(row.item.title == title && row.item.kind == "File" && row.item.rowLabel == label)
        #expect(row.item.isScopeResult)
    }

    @Test(arguments: ["~/Nowhere", "/Users/someone/Downloads/missing.txt", "Downloads", "x y.txt", "./Downloads", "~someone", ""])
    func aPathThatIsMissingOrRelativeAddsNothing(typed: String) {
        let contribution = provider.contribution(for: context(typed))
        #expect(contribution.pinned.isEmpty && contribution.ranked.isEmpty && contribution.appended.isEmpty)
    }

    @Test func aTextThatIsNotAPathNeverReachesTheDisk() {
        let asked = Asked()
        let watched = TypedLocationSearchProvider(home: { "/Users/someone" }, kind: {
            asked.add($0)
            return nil
        })
        for query in ["safari", "github.com/thaw-app", "notes.txt", "1.5*2", "files ~/x", "g github.com", "Downloads/x", ""] {
            _ = watched.contribution(for: context(query))
        }
        #expect(asked.paths.isEmpty)
        _ = watched.contribution(for: context("~/x"))
        #expect(asked.paths == ["/Users/someone/x"], "one lookup for a path, in its standard form")
    }

    // MARK: Among the other results

    @Test(arguments: ["github.com/thaw-app", "github.com", "localhost:3000", "https://example.com/a?b=c", "~/Downloads", "~", "/Users/someone/x y.txt"])
    func theRowLeadsAndTheRestStayAsTheyWereBeneathIt(typed: String) {
        let results = search(typed)
        #expect(results.with.count == results.without.count + 1)
        #expect(titles(Array(results.with.dropFirst())) == titles(results.without))
        let first = results.with.first?.item
        #expect(first?.isScopeResult == true)
        #expect(results.without.contains { $0.item.title == "Search Google for \u{201C}\(typed)\u{201D}" }, "the search for the same text is still there")
        #expect(results.without.contains { $0.id == "files-for:\(typed)" } && results.without.contains { $0.id == "ask-ai" })
    }

    @Test(arguments: [
        "safari", "saf", "1.5*2", "2+2", "3.14", "1.2.3", "10.5 km in miles", "notes.txt", "main.swift", "report.pdf", "a@b.com",
        "g github.com", "gh ~/Downloads", "note github.com", "ask github.com", "files ~/x", "open github.com", "~/Nowhere", "",
    ])
    func aTextThatOnlyLooksAlikeChangesNothing(typed: String) {
        let results = search(typed)
        #expect(titles(results.with) == titles(results.without))
    }

    @Test func theCalculatorAQuicklinkKeywordAndAnAppKeepTheTop() {
        #expect(search("1.5*2").with.first?.id == "calculator")
        #expect(search("10.5 km in miles").with.first?.id == "calculator")
        #expect(search("g github.com").with.first?.item.title == "Search Google for \u{201C}github.com\u{201D}")
        #expect(search("safari").with.first?.id == "app:/Applications/Safari.app")
        #expect(search("note github.com").with.first?.id == "note:new")
        #expect(search("ask github.com").with.first?.id == "ask-ai")
    }

    @Test func aQuicklinkKeywordThatStartsAPathKeepsItsSearch() {
        let slash = Quicklink(name: "Home", keyword: "/Users/someone/x", url: "https://example.com/?q={query}")
        let results = search("/Users/someone/x y.txt") { $0.quicklinks = [slash] }
        #expect(results.with.first?.item.title == "Search Home for \u{201C}y.txt\u{201D}")
        #expect(titles(results.with) == titles(results.without))
    }

    @Test func aScriptThatTakesTheTextAsItsArgumentsKeepsTheTop() {
        let script = ScriptCommand(
            file: URL(fileURLWithPath: "/tmp/home.sh"), title: "/Users/someone/x", packageName: nil, mode: .silent,
            needsConfirmation: false, icon: nil, arguments: []
        )
        let results = search("/Users/someone/x y.txt") { $0.scripts = [script] }
        #expect(results.with.first?.id == "script:home.sh")
        #expect(titles(results.with) == titles(results.without))
    }

    @Test(arguments: [
        "github.com", "github.com/thaw-app", "localhost:3000", "127.0.0.1", "1.1.1.1", "e.io", "pi.com", "5.ft/", "2.in/", "10.cm:80",
        "~", "~/Downloads", "/Users/someone/x y.txt",
    ])
    func whatTheCalculatorAnswersIsNeverAlsoOfferedAsAnAddressOrAPath(typed: String) {
        let pinned = provider.contribution(for: context(typed)).pinned
        #expect(Calculator.shared.evaluatePreview(typed) == nil || pinned.isEmpty)
        #expect(Calculator.shared.evaluatePreview(typed) != nil || pinned.count == 1)
    }

    // MARK: In the launcher

    @Test func filesFollowedByAPathIsStillTheFilesScope() {
        let context = SearchContext(query: "files ~/x")
        let match = RootSearch.scope(in: context, scopes: RootSearch.standardScopes())
        #expect(match?.scope.keyword == "files")
        #expect(match?.text == "~/x")
        #expect(provider.contribution(for: context).pinned.isEmpty)
    }

    @Test func returnOpensTheAddressThroughTheOpenerAndKeepsNoRecordOfIt() throws {
        let usage = try UsageStore(defaults: #require(UserDefaults(suiteName: "floe-typed-usage-\(UUID().uuidString)")))
        let model = makeModel(usage: usage)
        var opened: [URL] = []
        model.scopeResultOpener = {
            if case let .webAddress(address) = $0 {
                opened.append(address.url)
            }
        }
        model.query = "github.com/thaw-app"
        let row = try #require(model.results.first?.item)
        #expect(row.id == "web-address" && row.title == "Open github.com/thaw-app")
        #expect(model.selection == 0 && model.primaryActionTitle(for: row) == "Open")
        model.activate(row)
        #expect(opened.map(\.absoluteString) == ["https://github.com/thaw-app"])
        #expect(usage.records.isEmpty, "the address is not kept, under its text or any other id")

        model.toggleFavorite(row)
        #expect(model.settings.favorites.isEmpty)
        #expect(!LauncherModel.keepsItsPlace(row))
        #expect(model.rootActions(for: row).compactMap { $0?.title } == ["Open", "Copy Address"])
    }

    @Test func returnOpensATypedFolderOrFileAsAFileRowDoes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe typed \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)
        let usage = try UsageStore(defaults: #require(UserDefaults(suiteName: "floe-typed-usage-\(UUID().uuidString)")))
        let model = makeModel(usage: usage)
        var opened: [URL] = []
        model.scopeResultOpener = {
            if case let .file(found) = $0 {
                opened.append(found.url)
            }
        }
        // The temporary directory is reached through a symlink; the row keeps the path as it was typed.
        for (typed, isFolder) in [(folder.path + "/", true), (file.path, false), (folder.path + "/sub/../notes.txt", false)] {
            model.query = typed
            let row = try #require(model.results.first?.item)
            #expect(row.kind == "File" && row.title == (isFolder ? folder.lastPathComponent : "notes.txt"))
            model.activate(row)
            #expect(opened.last?.path == (isFolder ? folder.path : file.path))
            #expect(opened.last?.hasDirectoryPath == isFolder)
            model.toggleFavorite(row)
            let actions = model.rootActions(for: row).compactMap { $0?.title }
            #expect(actions.first == "Open" && actions.contains("Show in Finder") && actions.contains("Copy Path"))
            #expect(!actions.contains("Add to Favorites"))
        }
        #expect(opened.count == 3)
        #expect(usage.records.isEmpty && model.settings.favorites.isEmpty, "a file row is found just now: no usage record, no favorite")

        model.query = folder.path + "/missing.txt"
        #expect(model.results.allSatisfy { !$0.item.isScopeResult })
    }

    @Test func theLauncherLeavesTheOrdinaryQueriesAlone() {
        let model = makeModel()
        for query in ["safari", "1.5*2", "notes.txt", "1.2.3", "a@b.com"] {
            model.query = query
            #expect(model.results.allSatisfy { !$0.item.isScopeResult }, "\(query) has no typed row")
        }
        model.query = "safari"
        #expect(model.results.first?.id == "app:/Applications/Safari.app")
        model.query = "1.5*2"
        #expect(model.results.first?.id == "calculator")
    }
}

/// The paths a provider looked up, collected from its sendable closure.
private final nonisolated class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var paths: [String] {
        lock.withLock { stored }
    }

    func add(_ path: String) {
        lock.withLock { stored.append(path) }
    }
}
