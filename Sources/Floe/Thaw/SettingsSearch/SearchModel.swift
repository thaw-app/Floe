//
//  SearchModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Thaw 3's settings search model (Settings/Search/SearchModel.swift). Floe scores with
//  SearchRanker.diffScore instead of Ifrit's Fuse, adds the installed extensions to the index,
//  caps the result count, and carries the scroll anchor of the chosen result.

import Foundation
import Observation

// MARK: - SearchGroup

/// A group of search results that belong to the same settings pane.
struct SearchGroup: Identifiable {
    let pane: SettingsPage
    let label: SearchPaneLabel
    let entries: [SearchEntry]

    var id: SettingsPage {
        pane
    }
}

// MARK: - SearchModel

/// The model behind the settings search.
///
/// Matches the query against the index, then groups the ranked results by pane into
/// SearchGroups for SearchResultsList.
@MainActor
@Observable
final class SearchModel {
    /// More results than this is a sign to type more, not a list to read.
    static let resultLimit = 50

    var searchText = "" {
        didSet {
            updateDisplayedItems()
        }
    }

    private(set) var displayedGroups = [SearchGroup]()

    /// True while the query has something in it. Stored, and written only when it flips, so
    /// views that swap on it are not invalidated by every keystroke.
    private(set) var isSearching = false

    /// The anchor of the result that was just chosen, until its pane scrolls to it.
    var requestedAnchor: String?

    /// The result the arrow keys are on, by its id, which Return chooses. The first of each new search.
    private(set) var highlighted: String?

    /// The results in the order they are shown, group by group.
    var orderedResults: [SearchEntry] {
        displayedGroups.flatMap(\.entries)
    }

    /// Moves the highlight down the results or up them, and stops at either end.
    func moveHighlight(by offset: Int) {
        if let next = orderedResults.item(stepping: offset, from: { $0.id == highlighted }) {
            highlighted = next.id
        }
    }

    var highlightedEntry: SearchEntry? {
        orderedResults.first { $0.id == highlighted }
    }

    /// The search corpus. Starts with Floe's own panes; the extensions join when a search begins.
    @ObservationIgnored
    private var entries = SearchIndex.staticEntries

    var resultCount: Int {
        displayedGroups.reduce(0) { $0 + $1.entries.count }
    }

    /// Replaces what is searched.
    ///
    /// Called when a search begins, not when a pane is shown, so switching panes never pays for it.
    func setEntries(_ entries: [SearchEntry]) {
        self.entries = entries
        updateDisplayedItems()
    }

    /// Rebuilds displayedGroups from the current searchText.
    func updateDisplayedItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSearching == query.isEmpty {
            isSearching = !query.isEmpty
        }
        guard !query.isEmpty else {
            // The view renders the selected pane when the query is empty, so the model only
            // ever owns filtered results.
            if !displayedGroups.isEmpty {
                displayedGroups = []
            }
            highlighted = nil
            return
        }

        let scored = entries.compactMap { entry -> (item: SearchEntry, diffScore: Double)? in
            SearchRanker.diffScore(query: query, title: entry.title, keywords: entry.keywords, description: entry.descriptionText)
                .map { (item: entry, diffScore: $0) }
        }

        // Rank globally by relevance, then group by pane preserving the rank order within
        // each pane. Pane order follows the best-scoring entry.
        let ranked = SearchRanker.sortedByRelevance(scored).prefix(Self.resultLimit)

        var grouped: [SettingsPage: [SearchEntry]] = [:]
        var paneOrder: [SearchEntry] = []
        for entry in ranked {
            if grouped[entry.pane] == nil {
                paneOrder.append(entry)
            }
            grouped[entry.pane, default: []].append(entry)
        }

        displayedGroups = paneOrder.map { first in
            SearchGroup(pane: first.pane, label: first.paneLabel, entries: grouped[first.pane] ?? [])
        }
        highlighted = displayedGroups.first?.entries.first?.id
    }
}
