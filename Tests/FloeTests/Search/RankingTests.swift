//
//  RankingTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct FuzzyTests {
    @Test func prefixBeatsWordPrefixBeatsAcronymBeatsSubstringBeatsSubsequence() throws {
        let prefix = try #require(Fuzzy.score("saf", "Safari"))
        let wordPrefix = try #require(Fuzzy.score("mon", "Activity Monitor"))
        let acronym = try #require(Fuzzy.score("vsc", "Visual Studio Code"))
        let substring = try #require(Fuzzy.score("tivi", "Activity Monitor"))
        let subsequence = try #require(Fuzzy.score("sfr", "Safari"))
        #expect(prefix > wordPrefix)
        #expect(wordPrefix > acronym)
        #expect(acronym > substring)
        #expect(substring > subsequence)
    }

    @Test(arguments: [("xyz", "Safari"), ("iras", "Safari"), ("safarii", "Safari")])
    func charactersOutOfOrderOrMissingDoNotMatch(query: String, candidate: String) {
        #expect(Fuzzy.score(query, candidate) == nil)
    }

    @Test func matchingIgnoresCase() {
        #expect(Fuzzy.score("SAF", "safari") == Fuzzy.score("saf", "Safari"))
    }

    @Test func shorterCandidateWinsForTheSamePrefix() throws {
        let short = try #require(Fuzzy.score("cal", "Calendar"))
        let long = try #require(Fuzzy.score("cal", "Calculator and More Things"))
        #expect(short > long)
    }

    @Test func prefixPenaltyStopsAtTwentyCharacters() {
        let padded = "a" + String(repeating: "b", count: 60)
        #expect(Fuzzy.score("a", padded) == 80)
    }

    @Test func aLongCandidateIsScoredTheSameButNotHighlighted() throws {
        let query = "acegikmoqs"
        let long = String(repeating: "x", count: Fuzzy.positionBudget / query.count) + "abcdefghijklmnopqrstuvwxyz"
        let match = try #require(Fuzzy.match(query, long))
        #expect(match.score == Fuzzy.score(query, long), "the ranking does not change")
        #expect(match.matched.isEmpty, "a table of query by candidate this size is not built for a highlight")
        let short = try #require(Fuzzy.match(query, "abcdefghijklmnopqrstuvwxyz"))
        #expect(short.matched == [0, 2, 4, 6, 8, 10, 12, 14, 16, 18])
        let wide = try #require(Fuzzy.match("ÄCE", String(repeating: "ö", count: Fuzzy.positionBudget) + "äbcde"))
        #expect(wide.matched.isEmpty)
    }
}

struct FuzzyGradingTests {
    /// The matcher as it was before grading, kept to prove the upper tiers did not move.
    private func fixedTierScore(_ query: String, _ candidate: String) -> Int? {
        let query = query.lowercased()
        let candidate = candidate.lowercased()
        if candidate.hasPrefix(query) {
            return 100 - min(candidate.count - query.count, 20)
        }
        let words = candidate.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(query) }) {
            return 75
        }
        if String(words.compactMap(\.first)).hasPrefix(query) {
            return 70
        }
        if candidate.contains(query) {
            return 55
        }
        var remaining = Substring(query)
        for character in candidate where character == remaining.first {
            remaining = remaining.dropFirst()
        }
        return remaining.isEmpty ? 25 : nil
    }

    private static let candidates = [
        "Safari", "Activity Monitor", "Visual Studio Code", "Google Chrome", "ColorSync Utility", "System Settings",
        "Café Crème", "Über Notes", "foo_bar-baz.swift", "Sources/Floe/Ranking.swift", "A-B-C", "xaxbxc ab-c", "",
        "Privacy & Security", "1Password 7", "iPhone Mirroring", "ÉCOLE", "a\r\nb",
    ]

    private static let queries = [
        "", "s", "saf", "SAF", "mon", "vsc", "tivi", "sfr", "gchr", "cs", "abc", "é", "cré", "uber", "über", "fbb",
        "rank", "floe/r", "bar-b", "y m", "1p", "7", "pm", "ecole", "école", "ac", "b", "a b", "safarii", "&",
    ]

    @Test func theFourFixedTiersScoreExactlyAsBefore() {
        for query in Self.queries {
            for candidate in Self.candidates {
                let before = fixedTierScore(query, candidate)
                let after = Fuzzy.score(query, candidate)
                if let before, before >= 55 {
                    #expect(after == before, "\(query) in \(candidate)")
                } else {
                    #expect((after == nil) == (before == nil), "\(query) in \(candidate)")
                    #expect(after.map { (1 ..< 55).contains($0) } ?? true, "\(query) in \(candidate)")
                }
            }
        }
    }

    @Test func everyFixedTierOutranksTheBestScatteredMatch() throws {
        // Both letters sit on word starts at the very front: nothing scattered scores higher.
        let scattered = try #require(Fuzzy.score("ac", "A-B-C"))
        #expect(scattered == 54)
        let prefix = try #require(Fuzzy.score("a", "a" + String(repeating: "b", count: 60)))
        let wordPrefix = try #require(Fuzzy.score("mon", "Activity Monitor"))
        let initials = try #require(Fuzzy.score("vsc", "Visual Studio Code"))
        let substring = try #require(Fuzzy.score("tivi", "Activity Monitor"))
        #expect(prefix > wordPrefix)
        #expect(wordPrefix > initials)
        #expect(initials > substring)
        #expect(substring > scattered)
    }

    @Test func lettersAtWordStartsBeatLettersInsideAWord() throws {
        let atWordStarts = try #require(Fuzzy.score("gchr", "Google Chrome"))
        let insideWords = try #require(Fuzzy.score("gchr", "Bigger Machinery"))
        #expect(atWordStarts > insideWords)
    }

    @Test func lettersInARowBeatTheSameLettersSpreadOut() throws {
        let inRuns = try #require(Fuzzy.score("abcd", "zabzcd"))
        let spreadOut = try #require(Fuzzy.score("abcd", "zazbzczd"))
        #expect(inRuns > spreadOut)
    }

    @Test func aMatchThatStartsEarlyBeatsOneThatStartsLate() throws {
        let early = try #require(Fuzzy.score("sr", "safari"))
        let late = try #require(Fuzzy.score("sr", "xxxxxxsafari"))
        #expect(early > late)
    }

    @Test(arguments: [("-", "color-sync"), ("_", "color_sync"), (".", "color.sync"), ("/", "color/sync"), (" ", "color sync")])
    func aLetterAfterASeparatorCountsAsAWordStart(separator: String, candidate: String) throws {
        let separated = try #require(Fuzzy.score("os", candidate), "after \(separator)")
        let joined = try #require(Fuzzy.score("os", "colorsync"))
        #expect(separated > joined)
    }

    @Test func camelCaseHumpsCountAsWordStarts() throws {
        let humped = try #require(Fuzzy.match("os", "ColorSync"))
        let flat = try #require(Fuzzy.match("os", "Colorsync"))
        #expect(humped.score > flat.score)
        #expect(humped.matched == [1, 5])
        let accented = try #require(Fuzzy.score("oé", "ColorÉcole"))
        #expect(accented == humped.score, "humps are found outside ASCII too")
    }

    @Test func theBestAlignmentIsFoundNotTheFirst() throws {
        let match = try #require(Fuzzy.match("abc", "xaxbxc ab-c"))
        #expect(match.matched == [7, 8, 10])
        #expect(try match.score > #require(Fuzzy.score("abc", "xaxbxc")))
    }

    @Test(arguments: [
        ("sfr", "Safari"), ("gchr", "Google Chrome"), ("ac", "A-B-C"), ("abdefgh", "a-b-c-d-e-f-g-h x"),
        ("os", "ColorSync"), ("aba", "a-b-b-a"), ("abab", "ab-ab ab_ab"), ("pz", "pizza buzz"),
    ])
    func noScatteredMatchReachesTheSubstringScore(query: String, candidate: String) throws {
        let score = try #require(Fuzzy.score(query, candidate))
        #expect((1 ..< 55).contains(score))
    }

    @Test func keywordsStillRejectScatteredLetters() {
        #expect(Ranking.keywordScore("sfr", "Safari") == nil)
        #expect(Ranking.keywordScore("ac", "A-B-C") == nil, "even the best scattered match is not a keyword match")
        #expect(Ranking.keywordScore("far", "Safari") == 40)
    }

    @Test(arguments: [
        ("saf", "Safari", 97, [0, 1, 2]),
        ("mon", "Activity Monitor", 75, [9, 10, 11]),
        ("vsc", "Visual Studio Code", 70, [0, 7, 14]),
        ("tivi", "Activity Monitor", 55, [2, 3, 4, 5]),
        ("gchr", "Google Chrome", 50, [0, 7, 8, 9]),
    ])
    func matchedPositionsAreRightForEachTier(query: String, candidate: String, score: Int, matched: [Int]) throws {
        let match = try #require(Fuzzy.match(query, candidate))
        #expect(match.score == score)
        #expect(match.matched == matched)
        #expect(Fuzzy.score(query, candidate) == score, "score is the same number without the positions")
    }

    @Test func accentedLettersMatchThemselvesAndCountAsOneCharacter() throws {
        #expect(Fuzzy.score("é", "Café") == 55)
        #expect(Fuzzy.match("é", "Café")?.matched == [3])
        #expect(Fuzzy.score("CAFÉ", "café") == 100)
        #expect(Fuzzy.score("e", "Caf\u{E9}") == nil, "a plain letter is not its accented form")
        let scattered = try #require(Fuzzy.match("cé", "Crème brûlée"))
        #expect(scattered.matched == [0, 10])
        #expect((1 ..< 55).contains(scattered.score))
        #expect(Fuzzy.match("b", "a\r\nb")?.matched == [2], "a line break is one character")
    }

    @Test func uppercaseQueriesScoreLikeLowercaseOnes() {
        #expect(Fuzzy.score("GCHR", "google chrome") == Fuzzy.score("gchr", "google chrome"))
        #expect(Fuzzy.match("GCHR", "Google Chrome")?.matched == [0, 7, 8, 9])
    }

    @Test func anEmptyQueryIsAPrefixOfEverythingAndMatchesNoCharacters() throws {
        let match = try #require(Fuzzy.match("", "Safari"))
        #expect(match.score == 94)
        #expect(match.matched.isEmpty)
        #expect(Fuzzy.score("", "") == 100)
    }

    @Test func aQueryLongerThanTheCandidateDoesNotMatch() {
        #expect(Fuzzy.match("safari browser", "Safari") == nil)
        #expect(Fuzzy.score("ab", "a") == nil)
        #expect(Fuzzy.score("a", "") == nil)
    }

    @Test func menuBarItemsRankAGoodScatteredNameAboveAPoorOne() throws {
        let good = try #require(Ranking.menuBarScore(query: "gchr", name: "Google Chrome", owner: "x"))
        let poor = try #require(Ranking.menuBarScore(query: "gchr", name: "Bigger Machinery", owner: "x"))
        #expect(good > poor)
    }

    @Test func tenThousandCandidatesScoreWellWithinAKeystroke() {
        let words = ["Google", "Chrome", "System", "Settings", "Activity", "Monitor", "ColorSync", "Utility", "Terminal", "Notes"]
        let candidates = (0 ..< 10000).map { "\(words[$0 % 10]) \(words[($0 / 10) % 10]) \(words[($0 / 100) % 10]) \($0)" }
        let clock = ContinuousClock()
        var matches = 0
        let elapsed = clock.measure {
            for candidate in candidates where Fuzzy.score("gcset", candidate) != nil {
                matches += 1
            }
        }
        #expect(matches > 0)
        // Loose on purpose: an unoptimized build on a busy machine still has to pass.
        #expect(elapsed < .milliseconds(500), "took \(elapsed) for \(matches) matches")
    }
}

struct RankingTests {
    private let items: [RootItem] = [
        .command(Fixture.command("frontpage", extension: "hacker-news", title: "Hacker News")),
        .command(Fixture.command("planets", extension: "hello", title: "Browse Planets")),
        Fixture.app("Calculator"),
        Fixture.app("Calendar"),
        Fixture.app("Notes"),
        .menuBarSearch,
        .settings,
    ]

    private func id(_ title: String) -> String {
        items.first { $0.title == title }!.id
    }

    @Test(arguments: [
        (0.0, 4.0),
        (3599, 4),
        (3600, 2),
        (86399, 2),
        (86400, 1),
        (604_799, 1),
        (604_800, 0.5),
        (2_591_999, 0.5),
        (2_592_000, 0.25),
        (1e9, 0.25)
    ])
    func frecencyWeightFallsOffWithAge(age: TimeInterval, weight: Double) {
        #expect(Ranking.frecency(count: 1, age: age) == weight)
        #expect(Ranking.frecency(count: 3, age: age) == weight * 3)
    }

    @Test func exactAliasOutranksEverything() {
        #expect(Ranking.score(query: "hn", title: "Hacker News", alias: "hn") == 1000)
        #expect(Ranking.score(query: "HN", title: "Hacker News", alias: "hn") == 1000, "aliases match without regard to case")
    }

    @Test func aliasPrefixRanksAtLeastAsWellAsATitlePrefix() {
        #expect(Ranking.score(query: "ca", title: "Zebra", alias: "cal") == 95)
        #expect(Ranking.score(query: "ca", title: "Ca", alias: "cal") == 100, "a better title score is kept")
    }

    @Test func aliasThatDoesNotMatchFallsBackToTheTitle() {
        #expect(Ranking.score(query: "saf", title: "Safari", alias: "web") == Fuzzy.score("saf", "Safari"))
        #expect(Ranking.score(query: "saf", title: "Safari", alias: "") == Fuzzy.score("saf", "Safari"))
        #expect(Ranking.score(query: "zzz", title: "Safari", alias: nil) == nil)
    }

    @Test func browsingListsFavoritesThenSuggestionsThenCommandsThenApplications() {
        let usage = [id("Calendar"): 5.0, id("Hacker News"): 2.0]
        let results = Ranking.browse(items, favorites: [id("Notes")], frecency: { usage[$0] ?? 0 })

        #expect(results.map(\.item.title) == [
            "Notes",
            "Calendar",
            "Hacker News",
            "Browse Planets",
            "Search Menu Bar Items",
            "Floe Settings",
            "Calculator",
        ])
        #expect(results.map(\.section) == ["Favorites", "Suggestions", "Suggestions", "Commands", "Commands", "Commands", "Applications"])
    }

    @Test func browsingKeepsFavoritesInTheirSavedOrderAndOutOfSuggestions() {
        let favorites = [id("Calendar"), id("Notes"), "app:/Applications/Gone.app"]
        let results = Ranking.browse(items, favorites: favorites, frecency: { $0 == self.id("Calendar") ? 9 : 0 })

        #expect(results.prefix(2).map(\.item.title) == ["Calendar", "Notes"])
        #expect(results.filter { $0.section == "Suggestions" }.isEmpty, "a favorite is not suggested again")
        #expect(results.count == items.count, "a favorite that no longer exists is dropped, nothing else")
    }

    @Test func browsingSuggestsAtMostFiveItems() {
        let results = Ranking.browse(items, favorites: [], frecency: { _ in 1 })
        #expect(results.filter { $0.section == "Suggestions" }.count == 5)
    }

    @Test func equallyUsedSuggestionsKeepTheirOrder() {
        let few = Ranking.browse(items, favorites: [], frecency: { _ in 1 })
        #expect(few.filter { $0.section == "Suggestions" }.map(\.item.id) == items.prefix(5).map(\.id))

        // Enough items that the five are picked without sorting them all.
        let many = (1 ... 80).map { Fixture.app("App \($0)") }
        let results = Ranking.browse(many, favorites: [], frecency: { $0 == many[40].id ? 2 : 1 })
        #expect(results.filter { $0.section == "Suggestions" }.map(\.item.id) == ([many[40]] + many.prefix(4)).map(\.id))
    }

    @Test func browsingListsCommandsBeforeApplicationsInTheirOwnOrder() {
        let results = Ranking.browse(items, favorites: [], frecency: { _ in 0 })
        #expect(results.map(\.item.title) == ["Hacker News", "Browse Planets", "Search Menu Bar Items", "Floe Settings", "Calculator", "Calendar", "Notes"])
    }

    @Test func searchingOrdersByMatchThenUsage() {
        let unused = Ranking.search(items, query: "cal", favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(unused.map(\.item.title) == ["Calendar", "Calculator"])
        #expect(unused.allSatisfy { $0.section == nil })

        let usage = [id("Calculator"): 6.0]
        let used = Ranking.search(items, query: "cal", favorites: [], alias: { _ in nil }, frecency: { usage[$0] ?? 0 })
        #expect(used.map(\.item.title) == ["Calculator", "Calendar"])
    }

    @Test func usageBoostIsCappedSoAnExactAliasStillWins() {
        let results = Ranking.search(
            items,
            query: "c",
            favorites: [],
            alias: { $0.title == "Hacker News" ? "c" : nil },
            frecency: { $0 == self.id("Calculator") ? 1_000_000 : 0 }
        )
        #expect(results.first?.item.title == "Hacker News")
    }

    @Test func favoritesGetASmallBoostInSearch() {
        let results = Ranking.search(items, query: "cal", favorites: [id("Calculator")], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(results.map(\.item.title) == ["Calculator", "Calendar"])
    }

    @Test func searchRespectsTheLimit() {
        let many = (0 ..< 60).map { Fixture.app("App \($0)") }
        #expect(Ranking.search(many, query: "app", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }).count == 40)
        #expect(Ranking.search(many, query: "app", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }, limit: 3).count == 3)
    }

    @Test func menuBarItemsMatchOnNameAndLessStronglyOnOwner() throws {
        let byName = try #require(Ranking.menuBarScore(query: "tail", name: "Tailscale", owner: "Tailscale"))
        let byOwner = try #require(Ranking.menuBarScore(query: "codex", name: "Usage 86%", owner: "CodexBar"))
        #expect(byName > byOwner)
        #expect(try byOwner == #require(Fuzzy.score("codex", "CodexBar")) - 10)
        #expect(Ranking.menuBarScore(query: "zzz", name: "Tailscale", owner: "Tailscale") == nil)
    }

    @Test func aCommandAnswersToItsExtensionsNameBehindATitleThatMatches() {
        let brew: [RootItem] = [
            .command(Fixture.command("installed", extension: "brew", title: "Show Installed")),
            .command(Fixture.command("upgrade", extension: "brew", title: "Upgrade")),
            Fixture.app("Brewfile"),
            Fixture.app("Notes"),
        ]
        func found(_ query: String) -> [String] {
            Ranking.search(brew, query: query, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }).map(\.item.title)
        }

        #expect(found("brew") == ["Brewfile", "Show Installed", "Upgrade"])
        #expect(found("bw") == ["Brewfile"], "scattered letters of the extension's name do not find its commands")
    }

    @Test func aCommandAnswersToItsManifestKeywordsBehindATitleThatMatches() {
        var items = Fixture.command("items", extension: "vault", title: "Search Items")
        items.keywords = ["1p", "login"]
        let all: [RootItem] = [.command(items), Fixture.app("Login Items"), Fixture.app("Notes")]
        func found(_ query: String) -> [String] {
            Ranking.search(all, query: query, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }).map(\.item.title)
        }

        #expect(found("1p") == ["Search Items"])
        #expect(found("login") == ["Login Items", "Search Items"])
    }
}
