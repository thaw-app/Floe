//
//  AskAITests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct AskAITests {
    private let ask = Quicklink(name: "Ask Jeeves", keyword: "ask", url: "https://ask.com/web?q={query}")
    private let google = Quicklink(name: "Google", keyword: "g", url: "https://www.google.com/search?q={query}", isFallback: true)

    private func context(_ query: String, canAskAI: Bool = true, _ configure: (inout SearchContext) -> Void = { _ in }) -> SearchContext {
        var context = SearchContext(query: query)
        context.canAskAI = canAskAI
        configure(&context)
        return context
    }

    private func endpoint(_ baseURL: String, key: String? = "key") throws -> AIEndpoint {
        try #require(AIEndpoint(baseURL: baseURL, model: "small", apiKey: key))
    }

    // MARK: The keyword

    @Test func theKeywordASpaceAndSomeTextAreAQuestion() {
        #expect(AskAI.question(in: context("ask why is the sky blue")) == "why is the sky blue")
        #expect(AskAI.question(in: context("Ask Why")) == "Why", "the keyword counts in any case; the question is kept as typed")
        #expect(AskAI.question(in: context("  ask   why  ")) == "why", "the space around the question is not part of it")
    }

    @Test(arguments: ["ask", "ask ", "ask    ", "asking why", "task ask why", "why ask", ""])
    func theKeywordAloneOrInsideOtherTextIsAnOrdinarySearch(query: String) {
        #expect(AskAI.question(in: context(query)) == nil)
    }

    @Test func aQuicklinkOrAScriptThatAnswersToTheSameWordKeepsIt() {
        #expect(AskAI.question(in: context("ask why") { $0.quicklinks = [ask] }) == nil)
        let script = ScriptCommand(
            file: URL(fileURLWithPath: "/tmp/ask.sh"), title: "Ask", packageName: nil, mode: .silent,
            needsConfirmation: false, icon: nil, arguments: [ScriptArgument(placeholder: "text", optional: false)]
        )
        #expect(AskAI.question(in: context("ask why") { $0.scripts = [script] }) == nil)
    }

    // MARK: The rows

    @Test func theKeywordLeadsTheResultsWithTheQuestion() {
        let results = RootSearch.results(for: context("ask why is the sky blue"))
        #expect(results.first?.item.title == "Ask AI \u{201C}why is the sky blue\u{201D}")
        #expect(results.first?.item.kind == "AI")
        #expect(results.count(where: { $0.id == "ask-ai" }) == 1, "the row is not offered a second time at the bottom")
    }

    @Test func anyOtherTextEndsWithAnAskAIRowAfterTheFallbacksAndTheFileSearch() {
        let results = RootSearch.results(for: context("why is the sky blue") { $0.quicklinks = [google] })
        #expect(results.suffix(3).map(\.id) == ["quicklink-fallback:\(google.id.uuidString)", "files-for:why is the sky blue", "ask-ai"])
        #expect(results.last?.item.title == "Ask AI \u{201C}why is the sky blue\u{201D}")
    }

    @Test func theKeywordAloneAsksAboutTheWordItself() {
        #expect(RootSearch.results(for: context("ask")).last?.item.title == "Ask AI \u{201C}ask\u{201D}")
    }

    @Test(arguments: ["ask why is the sky blue", "why is the sky blue"])
    func neitherRowIsOfferedWhenNoSourceCanAnswer(query: String) {
        let results = RootSearch.results(for: context(query, canAskAI: false))
        #expect(!results.contains { $0.id == "ask-ai" })
    }

    @Test func anEmptySearchOffersNoQuestion() {
        #expect(!RootSearch.results(for: context("")).contains { $0.id == "ask-ai" })
        #expect(!RootSearch.results(for: context("   ")).contains { $0.id == "ask-ai" })
    }

    @Test func theRowKeepsNoPlaceOfItsOwn() {
        let row = RootItem.askAI("my secret question")
        #expect(row.id == "ask-ai", "the question is not part of what favorites or usage would store")
        #expect(row.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(row))
    }

    // MARK: Local or not

    @Test func appleIntelligenceAndAnAPIOnThisMacAreLocal() throws {
        #expect(AskAI.isOnThisMac(.appleIntelligence))
        #expect(try AskAI.isOnThisMac(.api(endpoint("http://localhost:11434/v1", key: nil))))
        #expect(try AskAI.isOnThisMac(.api(endpoint("http://127.0.0.1:1234/v1", key: nil))))
        #expect(try AskAI.isOnThisMac(.api(endpoint("http://[::1]:8080/v1", key: nil))))
    }

    @Test func theToolsAndARemoteAPIAreNot() throws {
        #expect(!AskAI.isOnThisMac(.tools))
        #expect(try !AskAI.isOnThisMac(.api(endpoint("https://api.openai.com/v1"))))
        #expect(try !AskAI.isOnThisMac(.api(endpoint("https://openrouter.ai/api/v1"))))
        #expect(try !AskAI.isOnThisMac(.api(endpoint("https://192.168.1.20:11434/v1"))), "another machine on the network is not this Mac")
        #expect(try !AskAI.isOnThisMac(.api(endpoint("https://localhost.example.com/v1"))))
        #expect(!AskAI.isOnThisMac(.api(nil)), "an API that is not filled in is not known to be local")
    }

    // MARK: Who answered

    @Test func theLineUnderTheAnswerNamesTheSourceAndWhereItRuns() throws {
        #expect(AskAI.source(for: .appleIntelligence, tool: nil) == AskAI.Source(line: "Apple Intelligence, on this Mac", isOnThisMac: true))
        #expect(AskAI.source(for: .tools, tool: "claude") == AskAI.Source(line: "The claude tool, on your account", isOnThisMac: false))
        #expect(AskAI.source(for: .tools, tool: "codex")?.line == "The codex tool, on your account")
        #expect(try AskAI.source(for: .api(endpoint("http://localhost:11434/v1", key: nil)), tool: nil) == AskAI.Source(line: "Ollama, on this Mac", isOnThisMac: true))
        #expect(try AskAI.source(for: .api(endpoint("http://localhost:1234/v1", key: nil)), tool: nil)?.line == "LM Studio, on this Mac")
        #expect(try AskAI.source(for: .api(endpoint("http://127.0.0.1:8080/v1", key: nil)), tool: nil)?.line == "127.0.0.1:8080, on this Mac")
        #expect(try AskAI.source(for: .api(endpoint("https://openrouter.ai/api/v1")), tool: nil) == AskAI.Source(line: "openrouter.ai", isOnThisMac: false))
        #expect(try AskAI.source(for: .api(endpoint("")), tool: "claude")?.line == "api.openai.com", "an installed tool is not named when the API answers")
    }

    @Test func nothingIsNamedWhenNothingCanAnswer() {
        #expect(AskAI.source(for: .tools, tool: nil) == nil)
        #expect(AskAI.source(for: .api(nil), tool: "claude") == nil)
    }

    // MARK: Availability

    @Test func availabilityIsAskedAgainOnlyAfterItsLifetime() {
        var now = Date(timeIntervalSince1970: 1000)
        var answers = [true, false]
        var asked = 0
        let check = AskAI.availabilityCheck(lifetime: 2, now: { now }, check: {
            asked += 1
            return answers.removeFirst()
        })
        #expect(check())
        now += 1.9
        #expect(check(), "the first answer still stands")
        #expect(asked == 1)
        now += 0.2
        #expect(!check())
        #expect(asked == 2)
    }
}
