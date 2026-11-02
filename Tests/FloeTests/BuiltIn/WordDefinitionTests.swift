//
//  WordDefinitionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

private actor DictionaryAnswers {
    nonisolated let requests = AsyncStream<String>.makeStream()
    private var pending: [String: CheckedContinuation<String?, Never>] = [:]

    func entry(for word: String) async -> String? {
        await withCheckedContinuation { continuation in
            pending[word] = continuation
            requests.continuation.yield(word)
        }
    }

    func answer(_ word: String, with entry: String) {
        pending.removeValue(forKey: word)?.resume(returning: entry)
    }
}

struct WordDefinitionTests {
    private let tide = "tide | tīd |\nnoun\n1 the alternate rising and falling of the sea"

    private static nonisolated func checkWorker() {
        #expect(Thread.isMainThread == false)
    }

    private func context(_ query: String, word: String = "tide", entry: String? = nil) -> SearchContext {
        var context = SearchContext(query: query)
        context.definitions = [WordDefinition(word: word, entry: entry ?? tide)]
        return context
    }

    @Test func theEntryIsPutOnOneLine() {
        #expect(WordDefinition(word: "Tide", entry: tide).text == "tide | tīd | noun 1 the alternate rising and falling of the sea")
    }

    @Test func theLinkOpensTheWordInTheDictionaryApp() {
        #expect(WordDefinition(word: "tide", entry: tide).link?.absoluteString == "dict://tide")
        #expect(WordDefinition(word: "high tide", entry: tide).link?.absoluteString == "dict://high%20tide")
    }

    @Test func defineAndAWordPinsTheEntryAlreadyRead() {
        let contribution = DefinitionSearchProvider().contribution(for: context("Define tide "))
        #expect(contribution.pinned.map(\.item.title) == ["tide | tīd | noun 1 the alternate rising and falling of the sea"])
        #expect(contribution.pinned.first?.item.kind == "Dictionary")
    }

    @Test func nothingIsPinnedWithoutAMatchingWordOrAnEntry() {
        let provider = DefinitionSearchProvider()
        for query in ["define", "define ", "define xyzzy", "tide", "defined tide"] {
            #expect(provider.contribution(for: context(query)).pinned.isEmpty, "\(query)")
        }
        #expect(provider.contribution(for: context("define ebb", word: "ebb", entry: " \n")).pinned.isEmpty)
        #expect(provider.contribution(for: SearchContext(query: "define tide")).pinned.isEmpty)
    }

    @Test func aQuicklinkWithTheSameKeywordKeepsIt() {
        var context = context("define tide")
        context.quicklinks = [Quicklink(name: "Wiktionary", keyword: "define", url: "https://en.wiktionary.org/wiki/{query}")]
        #expect(DefinitionSearchProvider().contribution(for: context).pinned.isEmpty)
    }

    @Test func aChosenKeywordTakesThePlaceOfDefine() {
        var context = context("dict tide")
        context.definitionKeyword = "dict"
        #expect(DefinitionSearchProvider().contribution(for: context).pinned.count == 1)

        var usual = self.context("dict tide")
        usual.definitionKeyword = WordDefinition.keyword
        #expect(DefinitionSearchProvider().contribution(for: usual).pinned.isEmpty)

        context = self.context("define tide")
        context.definitionKeyword = "dict"
        #expect(DefinitionSearchProvider().contribution(for: context).pinned.isEmpty, "the old word no longer looks up")
        #expect(KeywordHint.offered(in: context).contains { $0.keyword == "dict" && $0.example == "dict tide" })
    }

    @Test(arguments: [("dict", "dict"), ("  Dict  ", "dict"), ("look up", "look"), ("", "define"), ("   ", "define"), ("define", "define"), ("menu", "define"), ("Keywords", "define"), ("pause", "define"), ("?", "define"), (">", "define")])
    @MainActor
    func aKeywordSettingIsOneFreeWordOrTheUsualOne(setting: String, keyword: String) {
        #expect(WordDefinition.keyword(from: setting) == keyword)
    }

    @Test func theWordTypedComesFirstWithoutPossessivesAndUpToTheLimit() {
        #expect(WordDefinition.words(for: "tide", completions: ["tide", "tides", "tide's", "Tide", "Tides"]) == ["tide", "tides"])
        let many = (1 ... 20).map { "tide\($0)" }
        #expect(WordDefinition.words(for: "tide", completions: many).count == WordDefinition.listLimit)
    }

    @Test func aPartWordListsTheWordsItStartsThatTheDictionaryHas() async {
        let search = DefinitionSearch(
            lookup: { ["tide": "the sea rises", "tidal": "of tides"][$0] },
            completions: { _ in ["tidal", "tidbit", "tide"] }
        )
        await search.search(SearchContext(query: "define tid")) {}?.value
        #expect(search.definitions.map(\.word) == ["tidal", "tide"], "the part word and tidbit have no entry")
        var context = SearchContext(query: "define tid")
        context.definitions = search.definitions
        #expect(DefinitionSearchProvider().contribution(for: context).pinned.map(\.item.id) == ["definition:tidal", "definition:tide"])
    }

    @Test func lookupLeavesTheMainThreadAndPublishesOnlyOnceForTheSameWord() async {
        let search = DefinitionSearch(lookup: { word in
            Self.checkWorker()
            return word == "tide" ? "the sea rises" : nil
        }, completions: { _ in [] })
        var changes = 0
        let context = SearchContext(query: "define tide")
        let task = search.search(context) { changes += 1 }
        #expect(search.isSearching)
        #expect(search.definitions.isEmpty)
        await task?.value
        #expect(search.definitions.first?.text == "the sea rises")
        #expect(search.isSearching == false)
        await search.search(context) { changes += 1 }?.value
        #expect(changes == 1)
    }

    @Test func anOldAnswerCannotReplaceTheNewWordOrRestoreACancelledSearch() async {
        let answers = DictionaryAnswers()
        var requests = answers.requests.stream.makeAsyncIterator()
        let search = DefinitionSearch(lookup: { await answers.entry(for: $0) }, completions: { _ in [] })
        var changes = 0
        let old = search.search(SearchContext(query: "define tide")) { changes += 1 }
        #expect(await requests.next() == "tide")
        let current = search.search(SearchContext(query: "define ebb")) { changes += 1 }
        #expect(await requests.next() == "ebb")
        await answers.answer("ebb", with: "the sea falls")
        await current?.value
        await answers.answer("tide", with: "the sea rises")
        await old?.value
        #expect(search.definitions.map(\.word) == ["ebb"])
        #expect(changes == 1)

        let cancelled = search.search(SearchContext(query: "define flood")) { changes += 1 }
        #expect(await requests.next() == "flood")
        search.search(SearchContext(query: "other query")) { changes += 1 }
        await answers.answer("flood", with: "water")
        await cancelled?.value
        #expect(search.definitions.isEmpty)
        #expect(search.isSearching == false)
        #expect(changes == 1)
    }

    @Test func theLauncherPinsTheAsyncAnswerAndRemovesItForANewQuery() async {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        model.definitionSearch.completions = { _ in [] }
        model.definitionSearch.lookup = { word in
            Self.checkWorker()
            return word == "tide" ? "the sea rises" : nil
        }
        model.query = "define tide"
        model.refresh()
        #expect(model.isAwaitingResults)
        await model.definitionSearch.settled()
        #expect(model.results.first?.item.id == "definition:tide")
        #expect(model.results.first?.item.title == "the sea rises")
        #expect(model.selection == 0)
        #expect(model.isAwaitingResults == false)
        model.query = "define unknown"
        model.refresh()
        #expect(model.results.contains { $0.item.id.hasPrefix("definition:") } == false)
        await model.definitionSearch.settled()
        #expect(model.results.contains { $0.item.id.hasPrefix("definition:") } == false)
    }
}
