//
//  SearchScope.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A search of its own inside the root search: `files invoice` shows only the files scope's rows.
protocol SearchScope {
    /// The word that, followed by a space and some text, narrows the search to this scope.
    var keyword: String { get }
    /// The section title the rows show under.
    var title: String { get }
    /// What the empty list says when nothing matches.
    var emptyTitle: String { get }
    /// The text a query hands the scope; nil when the query is not one for it.
    func text(in context: SearchContext) -> String?
    /// The rows that are known at once.
    func results(for text: String, context: SearchContext) -> [RootItem]
    /// Rows that take time to find. Each batch replaces the rows shown; nil when `results` is all there is.
    func updates(for text: String, context: SearchContext) -> AsyncStream<[RootItem]>?
}

extension SearchScope {
    func text(in context: SearchContext) -> String? {
        context.text(after: keyword)
    }

    func updates(for _: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        nil
    }
}

/// A query that names a scope, split into the scope and the text to search it for.
struct ScopeMatch {
    let scope: any SearchScope
    let text: String

    /// The same for two queries that ask a scope the same thing.
    var query: String {
        scope.keyword + " " + text
    }

    func rows(_ items: [RootItem]) -> [RootResult] {
        items.map { RootResult(item: $0, section: scope.title) }
    }
}

extension RootSearch {
    /// Each model gets its own: a scope may hold the search it is running.
    static func standardScopes() -> [any SearchScope] {
        [FileSearchScope(), ClipboardSearchScope(), MenuBarSearchScope(), SSHSearchScope(), ProcessSearchScope(), PortSearchScope(), ReceiptsSearchScope(), AppleShortcutSearchScope()]
    }

    /// The scope a query names with its keyword (see `SearchContext.text(after:)`). The first scope
    /// that answers to the word decides, whether or not there is text for it.
    static func scope(in context: SearchContext, scopes: [any SearchScope]) -> ScopeMatch? {
        // The space is added back, so a scope that lists everything for its keyword alone is asked too.
        let query = context.trimmed.lowercased() + " "
        guard let scope = scopes.first(where: { query.hasPrefix($0.keyword.lowercased() + " ") }),
              let text = scope.text(in: context)
        else { return nil }
        return ScopeMatch(scope: scope, text: text)
    }
}

/// Follows the rows a search delivers later. Each search supersedes the one before it, so rows that
/// arrive for an older query are dropped.
final class SearchUpdates {
    /// Bumped per search: a batch is delivered only while its search is still the newest.
    private var generation = 0
    private var task: Task<Void, Never>?

    /// Returns whether there is anything to wait for. `finish` runs once the last batch is in.
    func follow(_ updates: AsyncStream<[RootItem]>?, deliver: @escaping ([RootItem]) -> Void, finish: @escaping () -> Void) -> Bool {
        cancel()
        guard let updates else { return false }
        let started = generation
        task = Task { @MainActor [weak self] in
            for await rows in updates {
                guard let self, started == generation else { return }
                deliver(rows)
            }
            guard let self, started == generation else { return }
            finish()
        }
        return true
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
