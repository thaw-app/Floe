//
//  SearchIndex.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Thaw 3's settings search index (Settings/Search/SearchIndex.swift), with the entry reshaped
//  for Floe: strings already in the user's language instead of localization keys, so the search
//  matches what is on screen, Floe's SettingsPage as the pane, and a scroll anchor where Thaw
//  has a disclosure. The entries themselves are Floe's and live in SettingsSearchEntries.swift.

import Foundation

// MARK: - SearchPaneLabel

/// How a pane is named above its group of results: the title and glyph its sidebar row shows.
struct SearchPaneLabel: Equatable {
    let title: String
    /// SF Symbol for Floe's own panes.
    let symbol: String?
    /// Manifest icon for an extension's pane, resolved against assetsPath.
    let icon: String?
    let assetsPath: String

    init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
        self.icon = nil
        self.assetsPath = ""
    }

    init(title: String, icon: String, assetsPath: String) {
        self.title = title
        self.symbol = nil
        self.icon = icon
        self.assetsPath = assetsPath
    }
}

// MARK: - SearchPane

/// A pane an entry can sit on, with the label its group of results is shown under.
struct SearchPane {
    let page: SettingsPage
    let label: SearchPaneLabel
}

// MARK: - SearchEntry

/// One searchable row in the settings search index.
struct SearchEntry: Identifiable {
    let id: String
    /// The control's label, as its pane shows it.
    let title: String
    let descriptionText: String?
    let pane: SettingsPage
    let paneLabel: SearchPaneLabel
    /// The section heading the control sits under, when its pane has sections.
    let section: String?
    /// Other words someone might type to find the control, translated as one list. Each is matched on its own.
    let keywords: [String]
    /// The id of the view to scroll to once the pane is showing; nil leaves the pane at its top.
    let anchor: String?

    init(
        id: String,
        title: String,
        descriptionText: String? = nil,
        pane: SearchPane,
        section: String? = nil,
        keywords: [String] = [],
        anchor: String? = nil
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.pane = pane.page
        self.paneLabel = pane.label
        self.section = section
        self.keywords = keywords
        self.anchor = anchor
    }
}

// MARK: - SearchIndex

enum SearchIndex {
    /// Entries for Floe's own panes, in pane order.
    ///
    /// Resolved once, since search reads it per keystroke. A pane adds its controls by declaring
    /// a static list in an extension of SearchIndex and appending it here.
    static let staticEntries: [SearchEntry] = paneEntries + appearanceEntries + privacyEntries + generalEntries + applicationsEntries + aiEntries + syncEntries
        + aboutEntries + commandsEntries + quicklinksEntries

    /// Returns the entries that belong to the given pane.
    static func entries(for pane: SettingsPage, in entries: [SearchEntry] = staticEntries) -> [SearchEntry] {
        entries.filter { $0.pane == pane }
    }
}
