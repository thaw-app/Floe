//
//  FallbackTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct FallbackTests {
    private let google = Quicklink(name: "Google", keyword: "g", url: "https://google.com/?q={query}", isFallback: true)
    private let docs = Quicklink(name: "Docs", keyword: "d", url: "https://docs.example/?q={query}")
    private let home = Quicklink(name: "Home", keyword: "home", url: "https://example.com", isFallback: true)
    private let translate = Fixture.command("translate", extension: "lingo", arguments: [Fixture.field("text", type: "text", required: true)])

    private func context(_ query: String, _ configure: (inout SearchContext) -> Void = { _ in }) -> SearchContext {
        var context = SearchContext(query: query)
        context.quicklinks = [google, docs, home]
        context.commands = [translate]
        configure(&context)
        return context
    }

    private func rows(_ context: SearchContext) -> [String] {
        FallbackSearchProvider().contribution(for: context).appended.map(\.id)
    }

    @Test(arguments: [Fallback.shell, .searchFiles, .askAI, .quicklink(UUID()), .command("lingo/translate")])
    func anIDReadsBackAsTheSameFallback(fallback: Fallback) {
        #expect(Fallback(id: fallback.id) == fallback)
    }

    @Test(arguments: ["", "quicklink:not-a-uuid", "command:", "spotlight"])
    func anIDThisVersionDoesNotKnowIsNoFallback(id: String) {
        #expect(Fallback(id: id) == nil)
    }

    @Test func untilTheUserChoosesTheyAreTheOnesFloeAlwaysHad() {
        let order = Fallback.order(chosen: nil, quicklinks: [google, docs, home])
        #expect(order == [.shell, .quicklink(google.id), .searchFiles, .askAI], "a quicklink to one page cannot take what was typed")
    }

    @Test func theChosenOrderIsKeptAndWhatThisVersionCannotReadIsSkipped() {
        let order = Fallback.order(chosen: ["ask-ai", "spotlight", "quicklink:" + docs.id.uuidString], quicklinks: [google, docs])
        #expect(order == [.askAI, .quicklink(docs.id)])
    }

    @Test func rowsFollowTheChosenOrderUnderOneSection() {
        let chosen = ["command:" + translate.id, "search-files", "quicklink:" + docs.id.uuidString]
        let contribution = FallbackSearchProvider().contribution(for: context("hola") { $0.fallbacks = chosen })
        #expect(contribution.appended.map(\.id) == ["fallback-command:" + translate.id, "files-for:hola", "quicklink-fallback:" + docs.id.uuidString])
        #expect(contribution.appended.allSatisfy { $0.section == "Fallbacks" })
        #expect(contribution.appended.first?.item.title == "Translate “hola”")
    }

    @Test func aFallbackThatCannotAnswerIsLeftOut() {
        let chosen = ["ask-ai", "shell", "quicklink:" + home.id.uuidString, "quicklink:" + UUID().uuidString, "command:gone/away"]
        #expect(rows(context("hola") { $0.fallbacks = chosen }).isEmpty, "no AI source, no command line, a page, a removed link, a removed command")
        #expect(rows(context("hola") { $0.fallbacks = chosen
            $0.canAskAI = true
        }) == ["ask-ai"])
    }

    @Test func askingByTheKeywordLeavesTheFallbackOut() {
        #expect(rows(context("ask why") { $0.fallbacks = ["ask-ai"]
            $0.canAskAI = true
        }).isEmpty, "the question already leads the results")
    }

    @Test func aSearchWithNothingTypedHasNoFallbacks() {
        #expect(rows(context("  ")).isEmpty)
    }

    @Test func noChosenFallbacksMeansNone() {
        #expect(rows(context("hola") { $0.fallbacks = [] }).isEmpty)
    }

    @Test func aCommandTakesTheTextInItsFirstArgumentWhenItAsksForNothingElse() {
        #expect(Fallback.accepts(Fixture.command("plain")))
        #expect(Fallback.accepts(translate))
        #expect(Fallback.arguments(for: translate, text: "hola") as? [String: String] == ["text": "hola"])
        #expect(Fallback.arguments(for: Fixture.command("plain"), text: "hola").isEmpty)
        let pick = Fixture.command("pick", arguments: [Fixture.field("lang", type: "dropdown", required: true)])
        let two = Fixture.command("two", arguments: [Fixture.field("a", type: "text"), Fixture.field("b", type: "text", required: true)])
        #expect(!Fallback.accepts(pick), "the first argument has to be text")
        #expect(!Fallback.accepts(two), "a second argument it needs would have to be asked for")
        #expect(!Fallback.accepts(Fixture.command("meter", mode: "menu-bar")))
    }

    @Test func thePageOffersTheBuiltInsTheSearchesAndTheCommandsThatTakeText() {
        let choices = Fallback.choices(quicklinks: [google, home], commands: [translate, Fixture.command("meter", mode: "menu-bar")])
        #expect(choices.map(\.id) == ["shell", "search-files", "ask-ai", "quicklink:" + google.id.uuidString, "command:" + translate.id])
        #expect(choices.map(\.row.title).contains("Search Google for “…”"))
        let chosen = Fallback.chosen(["command:" + translate.id, "command:gone/away", "ask-ai"], among: choices, quicklinks: [google])
        #expect(chosen.map(\.id) == ["command:" + translate.id, "ask-ai"])
    }

    @Test func movingSwapsWithTheNextShownRowAndLeavesTheOthersInPlace() {
        let ids = ["shell", "command:gone/away", "ask-ai", "search-files"]
        let shown = ["shell", "ask-ai", "search-files"]
        #expect(Fallback.moving("shell", by: 1, in: ids, shown: shown) == ["ask-ai", "command:gone/away", "shell", "search-files"])
        #expect(Fallback.moving("search-files", by: -1, in: ids, shown: shown) == ["shell", "command:gone/away", "search-files", "ask-ai"])
        #expect(Fallback.moving("shell", by: -1, in: ids, shown: shown) == ids, "the first stays first")
    }
}
