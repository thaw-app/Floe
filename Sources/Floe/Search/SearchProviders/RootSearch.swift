//
//  RootSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The root search: every provider is asked, and what they answer is merged into one list.
enum RootSearch {
    /// The order decides who is first among rows of one kind: emoji above events, a note above
    /// a keyword hit above the calculator, the catalog before quicklinks when scores tie.
    static let providers: [any SearchProvider] = [
        EmojiSearchProvider(),
        ShellCommandSearchProvider(),
        CheckpointSearchProvider(),
        ReminderSearchProvider(),
        EventSearchProvider(),
        TimerSearchProvider(),
        OutgoingDraftSearchProvider(),
        FocusSearchProvider(),
        CalendarSearchProvider(),
        NoteSearchProvider(),
        DefinitionSearchProvider(),
        AnswerRowSearchProvider(),
        QRCodeSearchProvider(),
        CatalogSearchProvider(),
        FinderSelectionSearchProvider(),
        SSHHostSearchProvider(),
        AppleShortcutSearchProvider(),
        QuicklinkSearchProvider(),
        TypedLocationSearchProvider(),
        CalculatorSearchProvider(),
        ScriptArgumentsSearchProvider(),
        AskAISearchProvider(),
        FallbackSearchProvider(),
    ]

    /// `sources` are the rows the optional sources have found so far (see `SourceSearch`).
    static func results(for context: SearchContext, providers: [any SearchProvider] = providers, sources: [RootResult] = []) -> [RootResult] {
        RootSearchAnswer(for: context, providers: providers).results(sources: sources)
    }

    fileprivate static func rank(_ contributions: [SearchContribution], context: SearchContext) -> [RootResult] {
        // What the user hid is left out here, before ranking, so it is in neither the list nor the search.
        let shown: ([RootItem]) -> [RootItem] = { items in context.hidden.isEmpty ? items : items.filter { !context.hidden.contains($0.id) } }
        guard !context.query.isEmpty else {
            return Ranking.browse(
                shown(contributions.flatMap(\.ranked)),
                searchOnly: shown(contributions.flatMap(\.searchOnly)),
                favorites: context.favorites,
                frecency: context.frecency
            )
        }
        return Ranking.search(
            shown(contributions.flatMap { $0.ranked + $0.searchOnly }),
            query: context.query,
            favorites: context.favorites,
            alias: { alias(for: $0, aliases: context.aliases) },
            frecency: context.frecency
        )
    }

    /// A quicklink that opens one page answers to its keyword; anything else to the alias the user gave it, if any.
    /// A quicklink that searches has no alias: its keyword alone must not lead the app of the same name (see `keywords`).
    static func alias(for item: RootItem, aliases: [String: String]) -> String? {
        if case let .quicklink(link, _, _, _) = item {
            return link.takesQuery ? nil : link.keyword
        }
        return item.settingsKey.flatMap { aliases[$0] }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Its rows wait on an answer worked out off the main thread, and are asked for again when it arrives. They are
/// pinned only, so the ranked rows stay as they were.
protocol LateSearchProvider: SearchProvider {}

extension DefinitionSearchProvider: LateSearchProvider {}
extension CalculatorSearchProvider: LateSearchProvider {}
/// It gives way to the calculator's answer.
extension TypedLocationSearchProvider: LateSearchProvider {}

/// What the providers answered for one search, asked and ranked once. Rows that arrive later join it without the
/// providers being asked again, so a row made fresh each time it is asked for, such as a UUID or a password, keeps its value.
struct RootSearchAnswer {
    private var context: SearchContext
    private let providers: [any SearchProvider]
    private var contributions: [SearchContribution]
    private let ranked: [RootResult]

    init(for context: SearchContext, providers: [any SearchProvider] = RootSearch.providers) {
        self.context = context
        self.providers = providers
        contributions = providers.map { $0.contribution(for: context) }
        ranked = RootSearch.rank(contributions, context: context)
    }

    /// Asks the late providers again, with the answers they wait on as they are now.
    mutating func update(definition: WordDefinition?, calculation: CalculatorRow?) {
        context.definition = definition
        context.calculation = calculation
        for (index, provider) in providers.enumerated() where provider is any LateSearchProvider {
            contributions[index] = provider.contribution(for: context)
        }
    }

    /// Top to bottom: sectioned, pinned, ranked, the sources' sections, appended.
    func results(sources: [RootResult] = []) -> [RootResult] {
        let pinned = contributions.flatMap(\.pinned)
        let pinnedIDs = Set(pinned.map(\.id))
        return contributions.flatMap(\.sectioned) + pinned + ranked.filter { !pinnedIDs.contains($0.id) } + sources + contributions.flatMap(\.appended)
    }
}
