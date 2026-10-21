//
//  SettingsSearchNavigation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Thaw 3's Settings/Search/SettingsSearchNavigation.swift. Thaw's pending request opens a
//  disclosure in the target pane; Floe's scrolls the pane to the chosen control, and opens
//  the tab that holds it on a pane with tabs.

import Foundation

/// Coordinates settings search and sidebar selection so a scroll request cannot leak into a
/// later, unrelated navigation.
@MainActor
enum SettingsSearchNavigation {
    static func selectSearchResult(_ entry: SearchEntry, selection: SettingsSelection, search: SearchModel) {
        search.requestedAnchor = entry.anchor
        search.requestedEntry = entry.id
        selection.page = entry.pane
        search.searchText = ""
    }

    /// A sidebar jump ends the search, or the detail column keeps stale results.
    static func selectSidebarPane(_ page: SettingsPage, selection: SettingsSelection, search: SearchModel) {
        search.searchText = ""
        guard selection.page != page else {
            return
        }
        search.requestedAnchor = nil
        search.requestedEntry = nil
        selection.page = page
    }

    /// Hands the pending anchor to the pane that is about to scroll to it, once.
    static func consumeAnchor(search: SearchModel) -> String? {
        guard let anchor = search.requestedAnchor else {
            return nil
        }
        search.requestedAnchor = nil
        return anchor
    }

    /// Hands the chosen result's id to the pane that opens the tab holding it, once.
    static func consumeEntry(search: SearchModel) -> String? {
        guard let entry = search.requestedEntry else {
            return nil
        }
        search.requestedEntry = nil
        return entry
    }
}
