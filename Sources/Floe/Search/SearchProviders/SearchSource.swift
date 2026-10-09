//
//  SearchSource.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A scope that may also add a few rows to an ordinary search, in a section of its own.
/// It is off until its switch in Settings, Privacy is turned on.
protocol SearchSource: SearchScope {
    /// The name its switch is stored under (`AppSettings.searchSources`).
    var id: String { get }
    /// The rows for an ordinary search that are known at once; by default what the scope shows.
    func inlineResults(for text: String, context: SearchContext) -> [RootItem]
    /// The rows for an ordinary search that take time to find. Each batch replaces the source's rows.
    func inlineUpdates(for text: String, context: SearchContext) -> AsyncStream<[RootItem]>?
}

extension SearchSource {
    func inlineResults(for text: String, context: SearchContext) -> [RootItem] {
        results(for: text, context: context)
    }

    func inlineUpdates(for text: String, context: SearchContext) -> AsyncStream<[RootItem]>? {
        updates(for: text, context: context)
    }
}

extension FileSearchScope: SearchSource {
    var id: String {
        SearchSourceInfo.files.id
    }
}

/// What the Privacy page says about a source, kept apart from the source so the page builds none.
struct SearchSourceInfo: Identifiable, Equatable {
    let id: String
    let title: String
    /// What the source reads, and that it stays on this Mac.
    let detail: String

    static let files = SearchSourceInfo(
        id: "files",
        title: String(localized: "Files", bundle: .floe),
        detail: String(localized: "Adds up to three files found by name, by Spotlight or by Fast file search when that is on. The search runs on this Mac and nothing leaves it. Type “files” and a name to see every match.", bundle: .floe, comment: "“files” is a word the user types. It is a command and stays in English.")
    )
    static let tabs = SearchSourceInfo(
        id: "tabs",
        title: String(localized: "Browser Tabs", bundle: .floe),
        detail: String(localized: "Asks each running browser (\(BrowserApp.all.map(\.name).joined(separator: ", "))) for its open tabs and matches their titles and addresses. macOS asks for permission the first time, once per browser. The list stays on this Mac. Type “tabs” and a word to see every match.", bundle: .floe, comment: "The placeholder is a list of browser names. “tabs” is a word the user types. It is a command and stays in English.")
    )
    static let all = [files, tabs]
}

extension RootSearch {
    /// Each model gets its own: a source may hold the search it is running.
    static func standardSources() -> [any SearchSource] {
        [FileSearchScope(), TabSearchSource()]
    }

    /// The sources whose switch is on, in the order their sections are shown.
    static func enabled(_ sources: [any SearchSource], in switches: Set<String>) -> [any SearchSource] {
        sources.filter { switches.contains($0.id) }
    }
}

/// The sources' rows for the ordinary search on screen. The ranked rows never wait for these:
/// they are asked for after the list is shown, and rows for a query that was typed past are dropped.
final class SourceSearch {
    /// How many rows one source may add to an ordinary search.
    static let rowLimit = 3
    /// Shorter queries match too much to be worth a search.
    static let minimumQueryLength = 3

    /// The search the rows belong to: the text and the sources asked.
    private var key: String?
    private var asked: [any SearchSource] = []
    private var found: [String: [RootItem]] = [:]
    private var followers: [String: SearchUpdates] = [:]
    private var pending: Set<String> = []

    /// True while a source's rows are still on their way.
    var isSearching: Bool {
        !pending.isEmpty
    }

    /// Each source's section, in the sources' order.
    var rows: [RootResult] {
        asked.flatMap { source in
            (found[source.id] ?? []).prefix(Self.rowLimit).map { RootResult(item: $0, section: source.title) }
        }
    }

    /// Asks the sources about a new query. A refresh for the same query leaves a running search alone.
    func search(_ context: SearchContext, sources: [any SearchSource], onChange: @escaping () -> Void) {
        let text = context.trimmed
        let wanted = text.count >= Self.minimumQueryLength ? sources : []
        let newKey = wanted.isEmpty ? nil : ([text] + wanted.map(\.id)).joined(separator: "\n")
        guard newKey != key else { return }
        cancel()
        key = newKey
        asked = wanted
        for source in wanted {
            let id = source.id
            found[id] = source.inlineResults(for: text, context: context)
            let follower = followers[id] ?? SearchUpdates()
            followers[id] = follower
            let isWaiting = follower.follow(source.inlineUpdates(for: text, context: context)) { [weak self] items in
                self?.found[id] = items
                onChange()
            } finish: { [weak self] in
                self?.pending.remove(id)
                onChange()
            }
            if isWaiting {
                pending.insert(id)
            }
        }
    }

    func cancel() {
        followers.values.forEach { $0.cancel() }
        key = nil
        asked = []
        found = [:]
        pending = []
    }
}
