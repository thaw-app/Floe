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
        CalendarSearchProvider(),
        NoteSearchProvider(),
        CatalogSearchProvider(),
        FinderSelectionSearchProvider(),
        SSHHostSearchProvider(),
        AppleShortcutSearchProvider(),
        QuicklinkSearchProvider(),
        TypedLocationSearchProvider(),
        CalculatorSearchProvider(),
        ScriptArgumentsSearchProvider(),
        SearchFilesRowProvider(),
        AskAISearchProvider(),
    ]

    /// `sources` are the rows the optional sources have found so far (see `SourceSearch`).
    static func results(for context: SearchContext, providers: [any SearchProvider] = providers, sources: [RootResult] = []) -> [RootResult] {
        merge(providers.map { $0.contribution(for: context) }, context: context, sources: sources)
    }

    /// Top to bottom: sectioned, pinned, ranked, the sources' sections, appended.
    static func merge(_ contributions: [SearchContribution], context: SearchContext, sources: [RootResult] = []) -> [RootResult] {
        let pinned = contributions.flatMap(\.pinned)
        let pinnedIDs = Set(pinned.map(\.id))
        let ranked = rank(contributions, context: context).filter { !pinnedIDs.contains($0.id) }
        return contributions.flatMap(\.sectioned) + pinned + ranked + sources + contributions.flatMap(\.appended)
    }

    private static func rank(_ contributions: [SearchContribution], context: SearchContext) -> [RootResult] {
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

    /// A quicklink answers to its keyword; anything else to the alias the user gave it, if any.
    static func alias(for item: RootItem, aliases: [String: String]) -> String? {
        if case let .quicklink(link, _, _, _) = item {
            return link.keyword
        }
        return item.settingsKey.flatMap { aliases[$0] }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
