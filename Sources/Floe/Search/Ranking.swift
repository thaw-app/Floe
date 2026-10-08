//
//  Ranking.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Foundation

nonisolated enum Fuzzy {
    /// Higher is better; nil means no match.
    static func score(_ query: String, _ candidate: String) -> Int? {
        evaluate(query, candidate, wantPositions: false)?.score
    }

    /// The score of a match that is a prefix, a word start, initials or one run of characters, and nil for anything looser.
    static func tierScore(_ query: String, _ candidate: String) -> Int? {
        evaluate(query, candidate, wantPositions: false, scattered: false)?.score
    }
}

extension RootItem {
    var isApp: Bool {
        if case .app = self {
            return true
        }
        return false
    }

    /// Other words a result answers to, matched like its title.
    var keywords: [String] {
        switch self {
        case let .command(command): [command.extensionTitle]
        case let .system(command): command.keywords
        case let .settingsPane(pane): pane.keywords
        case let .note(action, _): action == .new ? AppRole.notes.keywords : [String(localized: "add to note", bundle: .floe, comment: "A search keyword for the row that adds text to a note. Lowercase.")]
        case let .thaw(action): action.keywords
        case let .finderSelection(role, _): role.keywords
        case .clipboardApp: AppRole.clipboard.keywords
        case let .snippet(snippet): [snippet.keyword]
        case let .sshHost(host, _): host.keywords
        default: []
        }
    }
}

/// Orders the root search. Usage and settings come in as plain values, so this stays free of stored state.
enum Ranking {
    /// Use count weighted by recency: an item opened often but not lately fades behind one used today.
    static func frecency(count: Int, age: TimeInterval) -> Double {
        let weight: Double = switch age {
        case ..<3600: 4
        case ..<86400: 2
        case ..<604_800: 1
        case ..<2_592_000: 0.5
        default: 0.25
        }
        return Double(count) * weight
    }

    /// An exact alias wins outright; an alias prefix ranks with a title prefix.
    static func score(query: String, title: String, alias: String?) -> Int? {
        let titleScore = Fuzzy.score(query, title)
        guard let alias = alias?.lowercased(), !alias.isEmpty else { return titleScore }
        if alias == query.lowercased() {
            return 1000
        }
        if alias.hasPrefix(query.lowercased()) {
            return max(titleScore ?? 0, 95)
        }
        return titleScore
    }

    /// No query: favourites, then recently used, then commands and applications.
    /// `searchOnly` items are too many to list: they show here only as a favorite or a suggestion.
    static func browse(_ all: [RootItem], searchOnly: [RootItem] = [], favorites: [String], frecency: (String) -> Double) -> [RootResult] {
        let known = all + searchOnly
        let byID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let favoriteItems = favorites.compactMap { byID[$0] }
        let favoriteIDs = Set(favoriteItems.map(\.id))
        // Equally used items keep the order they came in, which a plain sort does not promise.
        let suggestions = known
            .filter { !favoriteIDs.contains($0.id) && frecency($0.id) > 0 }
            .min(count: 5) { frecency($0.id) > frecency($1.id) }
        let shown = favoriteIDs.union(suggestions.map(\.id))
        let (commands, apps) = all.filter { !shown.contains($0.id) }.partitioned(by: \.isApp)
        return favoriteItems.map { RootResult(item: $0, section: String(localized: "Favorites", bundle: .floe)) }
            + suggestions.map { RootResult(item: $0, section: String(localized: "Suggestions", bundle: .floe, comment: "A section title above results Floe suggests.")) }
            + commands.map { RootResult(item: $0, section: String(localized: "Commands", bundle: .floe)) }
            + apps.map { RootResult(item: $0, section: String(localized: "Applications", bundle: .floe)) }
    }

    /// With a query: match quality first, nudged by how often and how recently each item is used.
    static func search(
        _ all: [RootItem],
        query: String,
        favorites: [String],
        alias: (RootItem) -> String?,
        frecency: (String) -> Double,
        limit: Int = 40
    ) -> [RootResult] {
        // A set, so the favorite check inside the loop is one hash lookup and not a walk of the list.
        let favoriteIDs = Set(favorites)
        return all.compactMap { item -> (RootItem, Double)? in
            let scores = [score(query: query, title: item.title, alias: alias(item))] + item.keywords.map { keywordScore(query, $0) }
            guard let match = scores.compactMap(\.self).max() else { return nil }
            let boost = min(20, frecency(item.id) * 2) + (favoriteIDs.contains(item.id) ? 5 : 0)
            return (item, Double(match) + boost)
        }
        // Equal scores keep the order they came in, which a plain sort does not promise.
        .min(count: limit) { $0.1 > $1.1 }
        .map { RootResult(item: $0.0, section: nil) }
    }

    /// A keyword counts for less than the title it stands in for, and scattered letters in one do
    /// not count at all: an item with many keywords would otherwise answer to almost anything.
    static func keywordScore(_ query: String, _ keyword: String) -> Int? {
        // The tiers start at a substring's score, so nothing scattered is worked out only to be dropped.
        Fuzzy.tierScore(query, keyword).map { $0 - 15 }
    }

    /// A menu bar item matches on its name, or less strongly on the app that owns it.
    static func menuBarScore(query: String, name: String, owner: String) -> Int? {
        [Fuzzy.score(query, name), Fuzzy.score(query, owner).map { $0 - 10 }].compactMap(\.self).max()
    }
}
