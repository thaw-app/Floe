//
//  SearchProviderTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SearchProviderTests {
    private let github = Quicklink(name: "GitHub", keyword: "gh", url: "https://github.com/search?q={query}")
    private let google = Quicklink(name: "Google", keyword: "g", url: "https://www.google.com/search?q={query}", isFallback: true)
    private let deploy = ScriptCommand(
        file: URL(fileURLWithPath: "/tmp/deploy.sh"), title: "Deploy", packageName: nil, mode: .silent,
        needsConfirmation: false, icon: nil, arguments: []
    )

    private func context(_ query: String, _ configure: (inout SearchContext) -> Void = { _ in }) -> SearchContext {
        var context = SearchContext(query: query)
        configure(&context)
        return context
    }

    private func event(_ title: String, startsIn seconds: TimeInterval) -> CalendarEvent {
        let start = Date().addingTimeInterval(seconds)
        return CalendarEvent(
            identifier: title, title: title, startDate: start, endDate: start.addingTimeInterval(1800),
            isAllDay: false, calendarTitle: "Work", meetingURL: nil
        )
    }

    // MARK: The context

    @Test func theContextKeepsTheQueryAsTypedBesideItsTrimmedForm() {
        let context = SearchContext(query: "  gh floe \n")
        #expect(context.query == "  gh floe \n")
        #expect(context.trimmed == "gh floe")
    }

    // MARK: Each provider

    @Test func theCatalogOffersCommandsScriptsAppsAndBuiltInsAndKeepsPanesForSearching() {
        let pane = SystemSettingsPane(identifier: "com.apple.Displays", title: "Displays", symbol: "display", keywords: [])
        let snippet = Snippet(name: "Signature", keyword: "sig", text: "Best")
        let contribution = CatalogSearchProvider().contribution(for: context("") {
            $0.commands = [Fixture.command("planets")]
            $0.scripts = [deploy]
            $0.apps = [AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))]
            $0.settingsPanes = [pane]
            $0.snippets = [snippet]
            $0.notesApp = .antinote
            $0.thawActions = [.toggleSwap]
        })
        let ids = contribution.ranked.map(\.id)
        #expect(ids.prefix(3) == ["command:sample/planets", "script:deploy.sh", "app:/Applications/Safari.app"])
        #expect(Array(ids.dropFirst(3).prefix(5)) == [
            "builtin:menubar-search", "builtin:emoji-search", "builtin:clipboard-history", "builtin:file-search", "settings",
        ])
        #expect(ids.suffix(4) == ["snippet:\(snippet.id.uuidString)", "note:new", "note:append", "thaw:toggleSwap"])
        #expect(ids.contains("system:\(SystemCommand.allCases[0].rawValue)"))
        #expect(contribution.searchOnly.map(\.id) == ["settings-pane:com.apple.Displays"])
        #expect(contribution.pinned.isEmpty && contribution.sectioned.isEmpty && contribution.appended.isEmpty)
    }

    @Test func quicklinksRankByNameAndEndTheListAsFallbacks() {
        let contribution = QuicklinkSearchProvider().contribution(for: context("swift") { $0.quicklinks = [github, google] })
        #expect(contribution.ranked.map(\.id) == ["quicklink:\(github.id.uuidString)", "quicklink:\(google.id.uuidString)"])
        #expect(contribution.pinned.isEmpty, "no keyword starts the query")
        #expect(contribution.appended.map(\.id) == ["quicklink-fallback:\(google.id.uuidString)"])
        #expect(contribution.appended.first?.section == "Fallbacks")
        #expect(contribution.appended.first?.item.title == "Search Google for \u{201C}swift\u{201D}")
    }

    @Test func aQuicklinkKeywordAndASpacePinsThatSearchOnTop() {
        let contribution = QuicklinkSearchProvider().contribution(for: context(" gh floe ") { $0.quicklinks = [github, google] })
        #expect(contribution.pinned.map(\.item.title) == ["Search GitHub for \u{201C}floe\u{201D}"])
        #expect(contribution.pinned.first?.id == "quicklink:\(github.id.uuidString)", "it takes the place of the ranked GitHub row")
    }

    @Test func quicklinksStayOutOfABlankQuery() {
        for query in ["", "   "] {
            let contribution = QuicklinkSearchProvider().contribution(for: context(query) { $0.quicklinks = [github, google] })
            #expect(contribution.ranked.isEmpty && contribution.pinned.isEmpty && contribution.appended.isEmpty)
        }
    }

    @Test func theCalculatorPinsItsAnswerUnderItsOwnTitle() {
        let contribution = CalculatorSearchProvider().contribution(for: context("2+2"))
        #expect(contribution.pinned.map(\.item.title) == ["4"])
        #expect(contribution.pinned.first?.section == "Calculator")
        #expect(CalculatorSearchProvider().contribution(for: context("safari")).pinned.isEmpty)
        #expect(CalculatorSearchProvider().contribution(for: context("")).pinned.isEmpty)
    }

    @Test func aNoteKeywordWithTextPinsTheNoteItWouldMake() {
        let contribution = NoteSearchProvider().contribution(for: context("note buy milk"))
        #expect(contribution.pinned.map(\.id) == ["note:new"])
        #expect(contribution.pinned.first?.item.title == "New Note “buy milk”")
        #expect(NoteSearchProvider().contribution(for: context("note")).pinned.isEmpty, "the keyword alone is an ordinary search")
    }

    @Test func appendIsOnlyOfferedByAnAppThatCanAppend() {
        #expect(NoteSearchProvider().contribution(for: context("append more")).pinned.isEmpty)
        let antinote = NoteSearchProvider().contribution(for: context("append more") { $0.notesApp = .antinote })
        #expect(antinote.pinned.map(\.id) == ["note:append"])
    }

    @Test func aScriptTitleFollowedByArgumentsPinsTheScript() {
        let provider = ScriptArgumentsSearchProvider()
        #expect(provider.contribution(for: context("deploy staging") { $0.scripts = [deploy] }).pinned.map(\.id) == ["script:deploy.sh"])
        #expect(provider.contribution(for: context("deploy") { $0.scripts = [deploy] }).pinned.isEmpty, "the title alone ranks like any other row")
        #expect(provider.contribution(for: context("deployment") { $0.scripts = [deploy] }).pinned.isEmpty)
    }

    @Test func eventsAreSplitIntoTodayAndTomorrow() {
        // Noon tomorrow is never today, whatever the time the test runs at.
        let noonTomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(36 * 3600).timeIntervalSinceNow
        let events = [event("Standup", startsIn: 0), event("Review", startsIn: noonTomorrow)]
        let provider = CalendarSearchProvider { $0 == "agenda" ? events : [] }
        let contribution = provider.contribution(for: context("agenda"))
        #expect(contribution.sectioned.map(\.id) == ["event:Standup", "event:Review"])
        #expect(contribution.sectioned.map(\.section) == ["Today", "Tomorrow"])
        #expect(provider.contribution(for: context("safari")).sectioned.isEmpty)
    }

    @Test func aColonListsEmojiUnderTheirSection() {
        let contribution = EmojiSearchProvider().contribution(for: context(":smile"))
        #expect(!contribution.sectioned.isEmpty)
        #expect(contribution.sectioned.allSatisfy { $0.section == "Emoji & Symbols" && $0.id.hasPrefix("emoji:") })
        #expect(EmojiSearchProvider().contribution(for: context("smile")).sectioned.isEmpty, "without the colon it is an ordinary search")
    }

    @Test func everySearchEndsWithARowThatSearchesFilesForIt() {
        let contribution = SearchFilesRowProvider().contribution(for: context("invoice "))
        #expect(contribution.appended.map(\.id) == ["files-for:invoice "])
        #expect(SearchFilesRowProvider().contribution(for: context("")).appended.isEmpty)
    }

    // MARK: The merge

    private struct Fixed: SearchProvider {
        let fixed: SearchContribution

        func contribution(for _: SearchContext) -> SearchContribution {
            fixed
        }
    }

    @Test func theMergePutsSectionedRowsFirstThenPinnedThenRankedThenAppended() throws {
        let answer = RootItem.calculator(expression: "2+2", result: "4")
        let providers: [any SearchProvider] = [
            Fixed(fixed: SearchContribution(appended: [RootResult(item: .searchFiles("saf"), section: nil)])),
            Fixed(fixed: SearchContribution(ranked: [Fixture.app("Safari")])),
            Fixed(fixed: SearchContribution(pinned: [RootResult(item: answer, section: "Calculator")])),
            Fixed(fixed: SearchContribution(sectioned: [RootResult(item: .event(event("Standup", startsIn: 0)), section: "Today")])),
        ]
        let results = RootSearch.results(for: context("saf"), providers: providers)
        #expect(results.map(\.id) == ["event:Standup", "calculator", "app:/Applications/Safari.app", "files-for:saf"])
    }

    @Test func rowsOfOneKindKeepTheOrderOfTheirProviders() {
        let first = Fixed(fixed: SearchContribution(
            pinned: [RootResult(item: .note(.new, text: "a"), section: nil)],
            appended: [RootResult(item: .searchFiles("one"), section: nil)]
        ))
        let second = Fixed(fixed: SearchContribution(
            pinned: [RootResult(item: .script(deploy), section: nil)],
            appended: [RootResult(item: .searchFiles("two"), section: nil)]
        ))
        let results = RootSearch.results(for: context("x"), providers: [first, second])
        #expect(results.map(\.id) == ["note:new", "script:deploy.sh", "files-for:one", "files-for:two"])
    }

    @Test func aPinnedRowTakesThePlaceOfTheRankedRowWithItsId() {
        let ranked = Fixed(fixed: SearchContribution(ranked: [.script(deploy), Fixture.app("Deployer")]))
        let pinned = Fixed(fixed: SearchContribution(pinned: [RootResult(item: .script(deploy), section: nil)]))
        let results = RootSearch.results(for: context("deploy"), providers: [ranked, pinned])
        #expect(results.map(\.id) == ["script:deploy.sh", "app:/Applications/Deployer.app"])
    }

    @Test func withoutAQuerySearchOnlyRowsShowOnlyAsFavoritesOrSuggestions() {
        let displays = RootItem.settingsPane(SystemSettingsPane(identifier: "displays", title: "Displays", symbol: "display", keywords: []))
        let sound = RootItem.settingsPane(SystemSettingsPane(identifier: "sound", title: "Sound", symbol: "speaker", keywords: []))
        let provider = Fixed(fixed: SearchContribution(ranked: [Fixture.app("Safari")], searchOnly: [displays, sound]))
        let browsing = RootSearch.results(for: context("") { $0.favorites = [displays.id] }, providers: [provider])
        #expect(browsing.map(\.id) == [displays.id, "app:/Applications/Safari.app"])
        #expect(browsing.map(\.section) == ["Favorites", "Applications"])
        let searching = RootSearch.results(for: context("sound"), providers: [provider])
        #expect(searching.map(\.id) == [sound.id])
    }

    @Test func rankingReadsAliasesFavoritesAndFrecencyFromTheContext() {
        let provider = Fixed(fixed: SearchContribution(ranked: [Fixture.app("Safari"), Fixture.app("Sandbox")]))
        let sandbox = "app:/Applications/Sandbox.app"
        #expect(RootSearch.results(for: context("sa"), providers: [provider]).first?.id == "app:/Applications/Safari.app")
        #expect(RootSearch.results(for: context("sa") { $0.frecency = { $0 == sandbox ? 9 : 0 } }, providers: [provider]).first?.id == sandbox)
        #expect(RootSearch.results(for: context("zz") { $0.aliases = [sandbox: "zz"] }, providers: [provider]).map(\.id) == [sandbox])
    }

    @Test func aQuicklinkAnswersToItsKeywordAndOtherRowsToTheirAlias() {
        let link = RootItem.quicklink(github, queryText: "", fallback: false, keywordSearch: false)
        #expect(RootSearch.alias(for: link, aliases: [:]) == "gh")
        #expect(RootSearch.alias(for: .settings, aliases: ["settings": "s"]) == nil, "a row without a settings key has no alias")
        #expect(RootSearch.alias(for: .fileSearch, aliases: [RootItem.fileSearchKey: "f"]) == "f")
        #expect(RootSearch.alias(for: .fileSearch, aliases: [RootItem.fileSearchKey: ""]) == nil)
    }

    // MARK: The whole search

    @Test func theStandardProvidersLayOutAKeywordSearchAsBefore() {
        let results = RootSearch.results(for: context("gh floe") { $0.quicklinks = [github, google] })
        #expect(results.map(\.id) == [
            "quicklink:\(github.id.uuidString)",
            "quicklink-fallback:\(google.id.uuidString)",
            "files-for:gh floe",
        ])
    }

    @Test func aNoteLeadsAKeywordHitWhichLeadsTheCalculator() {
        let note = Quicklink(name: "Notes Site", keyword: "note", url: "https://example.com/?q={query}")
        let noted = RootSearch.results(for: context("note milk") { $0.quicklinks = [note] })
        #expect(noted.map(\.id) == ["note:new", "quicklink:\(note.id.uuidString)", "files-for:note milk"])

        let two = Quicklink(name: "Twos", keyword: "2", url: "https://example.com/?q={query}")
        let summed = RootSearch.results(for: context("2 + 2") { $0.quicklinks = [two] })
        #expect(summed.map(\.id) == ["quicklink:\(two.id.uuidString)", "calculator", "files-for:2 + 2"])
    }
}
