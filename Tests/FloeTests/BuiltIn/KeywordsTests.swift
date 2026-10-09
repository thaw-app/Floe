//
//  KeywordsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct KeywordsTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-keywords-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A context with everything a keyword may need switched on and there.
    private func everything(_ query: String = "keywords") -> SearchContext {
        var context = SearchContext(query: query)
        context.shell = ShellSettings()
        context.searchSources = [SearchSourceInfo.files.id, SearchSourceInfo.tabs.id]
        context.sshHosts = [SSHHost(alias: "web")]
        context.shortcuts = [AppleShortcut(name: "Set Focus", identifier: "1")]
        context.notesApp = .folder
        context.canAskAI = true
        return context
    }

    private func keywords(_ context: SearchContext) -> [String] {
        KeywordHint.offered(in: context).map(\.keyword)
    }

    // MARK: The table

    @Test func everyKeywordTheSearchAnswersToHasARow() {
        let own = [KeywordSearchScope.word, KeywordSearchScope.mark]
        let scoped = (RootSearch.standardScopes().map(\.keyword) + RootSearch.standardSources().map(\.keyword)).filter { !own.contains($0) }
        let typed = [
            CommandPrefix.greaterThan.rawValue, Checkpoint.keyword, Processes.keyword, Processes.portKeyword, ReminderDraft.keyword, EventDraft.keyword,
            TimerDraft.keyword, FocusRequest.keyword, AskAI.keyword, EmojiSearchProvider.prefix,
        ] + OutgoingDraft.Kind.allCases.map(\.keyword) + NoteAction.allCases.map(\.keyword)
        let listed = KeywordHint.all.map(\.keyword)
        #expect(Set(listed) == Set(scoped + typed), "a keyword that is added gets a row, and one that is gone loses it")
        #expect(Set(listed).count == listed.count, "one row each")
    }

    @Test func eachRowHasAnExampleThatStartsWithItsKeywordAndSaysWhatItDoes() {
        for hint in KeywordHint.all {
            #expect(hint.example.hasPrefix(hint.keyword), "\(hint.keyword)")
            #expect(!hint.detail.isEmpty, "\(hint.keyword)")
            #expect(hint.example == hint.keyword || hint.example.hasPrefix(hint.typed), "\(hint.keyword)")
        }
        let remind = KeywordHint.all.first { $0.keyword == "remind" }
        #expect(remind?.example == "remind call mom tomorrow at 5pm")
        #expect(remind?.detail == "Add a reminder")
        #expect(remind?.typed == "remind ")
        #expect(KeywordHint.all.first { $0.keyword == ":" }?.typed == ":", "an emoji is named straight after the colon")
    }

    // MARK: What is offered

    @Test func withEverythingOnEveryKeywordIsOffered() {
        #expect(keywords(everything()) == KeywordHint.all.map(\.keyword))
    }

    @Test func aKeywordThatIsOffOrHasNothingBehindItIsLeftOut() {
        var context = everything()
        context.shell.runs = false
        #expect(!keywords(context).contains(">"))

        context = everything()
        context.searchSources = [SearchSourceInfo.tabs.id]
        #expect(!keywords(context).contains("files"))
        #expect(keywords(context).contains("tabs"))
        context.searchSources = []
        #expect(!keywords(context).contains("tabs"))

        context = everything()
        context.sshHosts = []
        context.shortcuts = []
        context.canAskAI = false
        #expect(Set(KeywordHint.all.map(\.keyword)).subtracting(keywords(context)) == ["ssh", "shortcuts", "ask"])

        context = everything()
        context.notesApp = .appleNotes
        #expect(!keywords(context).contains { ["append", "todo", "log"].contains($0) }, "Apple Notes has no note to add a line to")
        #expect(keywords(context).contains("note"))
        context.notesApp = .antinote
        #expect(keywords(context).contains("append"))
        #expect(!keywords(context).contains { ["todo", "log"].contains($0) }, "a task and a journal line are a folder's")

        let bare = keywords(SearchContext(query: "keywords"))
        #expect(!bare.contains { [">", "files", "tabs", "ssh", "shortcuts", "ask"].contains($0) }, "a context made by hand has them all off")
        #expect(bare.contains("remind"))
    }

    @Test func theShellRowIsWrittenWithThePrefixTheUserChose() throws {
        var context = everything()
        context.shell.prefix = .dollar
        let row = try #require(KeywordHint.offered(in: context).first { $0.need == .shell })
        #expect(row.keyword == "$")
        #expect(row.example == "$ brew update")
        #expect(row.typed == "$ ")
    }

    // MARK: The scope

    @Test(arguments: ["keywords", "Keywords", "?", " ? "])
    func theWordOrAQuestionMarkAloneListsThemAll(query: String) throws {
        let context = everything(query)
        let match = try #require(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()))
        #expect(match.scope is KeywordSearchScope)
        #expect(match.scope.title == "Keywords")
        #expect(match.text.isEmpty)
        #expect(match.scope.results(for: match.text, context: context).map(\.title) == KeywordHint.all.map(\.example))
    }

    @Test(arguments: [("keywords remind", ["remind"]), ("? calendar", ["event"]), ("? draft", ["mail", "message"]), ("keywords a line", ["append", "log"]), ("? nothing like this", [])])
    func typingMoreNarrowsTheListByThoseWords(query: String, found: [String]) throws {
        let context = everything(query)
        let match = try #require(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()))
        #expect(match.scope.results(for: match.text, context: context).map(\.id) == found.map { "keyword:\($0)" })
    }

    @Test(arguments: ["keyword", "?what", "keywordsx", "what?"])
    func anythingElseIsAnOrdinarySearch(query: String) {
        let scopes: [any SearchScope] = [KeywordSearchScope(), KeywordSearchScope(keyword: KeywordSearchScope.mark)]
        #expect(RootSearch.scope(in: everything(query), scopes: scopes) == nil)
    }

    // MARK: The row

    @Test func aRowShowsItsExampleAndWhatItDoesAndIsNoFavorite() throws {
        let hint = try #require(KeywordHint.all.first { $0.keyword == "timer" })
        let row = RootItem.keyword(hint)
        #expect(row.title == "timer 10 minutes tea")
        #expect(row.rowLabel == "Start a countdown")
        #expect(row.kind == "Keyword")
        #expect(row.id == "keyword:timer")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(row))
        #expect(!LauncherModel.canBeHidden(row))
    }

    @Test func returnPutsTheKeywordAndASpaceIntoTheSearch() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try #require(UserDefaults(suiteName: "floe-keywords-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        let usage = UsageStore(defaults: defaults)
        let scopes: [any SearchScope] = [KeywordSearchScope(), KeywordSearchScope(keyword: KeywordSearchScope.mark)]
        let model = LauncherModel(settings: settings, usage: usage, snapshot: CatalogSnapshot(apps: [], commands: []), scopes: scopes, sources: [])
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "?"
        #expect(model.results.first?.section == "Keywords")
        #expect(model.results.first?.item.title == "> brew update", "shell commands are on until switched off")
        settings.shell.runs = false
        model.query = "? remind"
        let row = try #require(model.results.first?.item)
        #expect(model.results.count == 1)
        #expect(model.primaryActionTitle(for: row) == "Type Keyword")
        #expect(model.rootActions(for: row).compactMap { $0?.title } == ["Type Keyword"])

        let focus = model.focusToken
        model.activate(row)
        #expect(model.query == "remind ")
        #expect(model.focusToken == focus + 1, "the field takes the keys again")
        #expect(hidden == 0, "the panel stays for the rest to be typed")
        #expect(model.receipts.all.isEmpty)
        #expect(usage.frecency(of: row.id) == 0)
        model.toggleFavorite(row)
        #expect(settings.favorites.isEmpty)

        model.query = "keywords"
        #expect(!model.results.contains { $0.item.id == "keyword:>" }, "switched off, the prefix is not listed")
    }
}
