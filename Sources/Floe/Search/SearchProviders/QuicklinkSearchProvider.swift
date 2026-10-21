//
//  QuicklinkSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Quicklinks by name or keyword among the ranked rows, and as `keyword rest` on top. The ones that search
/// can also be fallbacks (see `FallbackSearchProvider`).
struct QuicklinkSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        let text = context.trimmed
        guard !text.isEmpty else { return SearchContribution() }
        let links = context.quicklinks
        return SearchContribution(
            // Names and keywords rank alongside everything else, through the keyword alias.
            ranked: links.map { RootItem.quicklink($0, queryText: text, fallback: false, keywordSearch: false) },
            pinned: Self.keywordSearchResult(query: text, links: links).map { [$0] } ?? []
        )
    }

    /// The `keyword rest` row for a query starting with a quicklink's keyword and a space, if any:
    /// `gh floe` offers Search GitHub for "floe" first.
    static func keywordSearchResult(query: String, links: [Quicklink]) -> RootResult? {
        guard let match = links.first(where: { query.hasPrefix($0.keyword + " ") }) else { return nil }
        let rest = String(query.dropFirst(match.keyword.count + 1))
        return RootResult(item: .quicklink(match, queryText: rest, fallback: false, keywordSearch: true), section: nil)
    }
}
