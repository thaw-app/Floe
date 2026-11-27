//
//  TypoMatchTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct TypoMatchTests {
    /// The queries from issue 112: a wrong, swapped, missing or extra letter.
    @Test(arguments: [
        ("gork", "Grok"), ("slakc", "Slack"), ("cjrome", "Google Chrome"), ("chorme", "Google Chrome"),
        ("notse", "Notes"), ("safarii", "Safari"), ("calandr", "Calendar"),
    ])
    func aTypoStillFindsTheApp(query: String, name: String) {
        #expect(Fuzzy.score(query, name) == nil, "the normal match misses it")
        #expect(TypoMatch.score(query, name) != nil)
    }

    @Test func aShortQueryGetsNoTypos() {
        #expect(TypoMatch.score("sax", "Safari") == nil)
        #expect(TypoMatch.allowance(forLength: 3) == 0)
        #expect(TypoMatch.allowance(forLength: 4) == 1)
        #expect(TypoMatch.allowance(forLength: 6) == 1)
        #expect(TypoMatch.allowance(forLength: 7) == 2)
    }

    @Test func tooManyTyposOrNoStartInCommonFindNothing() {
        #expect(TypoMatch.score("xbcd", "Slack") == nil)
        #expect(TypoMatch.score("maps", "Mail") == nil, "two letters wrong in four is too many")
    }

    @Test func fewerTyposAndTheStartOfTheNameScoreHigher() throws {
        let nameStart = try #require(TypoMatch.score("chorme", "Chrome"))
        let laterWord = try #require(TypoMatch.score("chorme", "Google Chrome"))
        let twoTypos = try #require(TypoMatch.score("calandr", "Calendar"))
        #expect(nameStart == 9)
        #expect(laterWord == 8)
        #expect(twoTypos < laterWord)
        #expect([nameStart, laterWord, twoTypos].allSatisfy { $0 < 10 }, "under the weakest match without typos")
    }

    @Test func otherScriptsAreLeftToTheNormalMatch() {
        #expect(TypoMatch.score("微信微信", "微信") == nil)
        #expect(TypoMatch.score("wexin", "微信") == nil)
    }

    @Test func aQueryWithSymbolsMatchingExactlyStaysInTheBand() {
        #expect(TypoMatch.score("c++ ", "C++ Builder") == 9)
    }
}

struct TypoRankingTests {
    private func app(_ name: String, otherNames: [String] = [], spellings: [String] = []) -> RootItem {
        .app(AppEntry(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"), otherNames: otherNames, spellings: spellings))
    }

    private func search(_ items: [RootItem], _ query: String) -> [String] {
        Ranking.search(items, query: query, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }).map(\.item.title)
    }

    @Test func aTypoMatchRanksUnderEveryMatchWithoutOne() {
        let items = [app("Slack"), app("Scrollback Kit")]
        #expect(search(items, "slakc") == ["Slack"])
        #expect(search(items, "slck") == ["Slack", "Scrollback Kit"], "a scattered match without typos still comes first")
    }

    @Test func onlyAppsGetTypos() {
        let command = RootItem.system(.playPause)
        #expect(TypoMatch.score("plsy", command.title) != nil, "it would match as an app")
        #expect(search([command], "plsy").isEmpty)
    }

    @Test func anAppAnswersToItsOtherNamesAsToItsTitle() {
        let items = [app("WeChat", otherNames: ["微信"], spellings: ["wei xin", "weixin"]), app("Notes", otherNames: ["备忘录"], spellings: ["bei wang lu", "beiwanglu"])]
        #expect(search(items, "微信") == ["WeChat"])
        #expect(search(items, "weixin") == ["WeChat"])
        #expect(search(items, "bwl") == ["Notes"], "the initials of the Latin spelling")
        #expect(search(items, "beiwang") == ["Notes"])
    }

    @Test func anOtherNameScoresLikeTheTitleAndASpellingLikeAKeyword() throws {
        let other = try #require(Ranking.search([app("System Settings", otherNames: ["Settings"])], query: "settings", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }).first)
        #expect(other.item.title == "System Settings")
        let typoOnOther = search([app("System Settings", otherNames: ["Settings"])], "setings")
        #expect(typoOnOther == ["System Settings"], "the typo fallback reads the other names too")
    }
}
