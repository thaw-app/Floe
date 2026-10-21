//
//  SettingsTabs.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// A settings page's tab, which knows which of the page's search results it holds.
protocol SettingsTab: ThawTab, CaseIterable where AllCases == [Self] {
    /// The tab holding a search result, by the result's id; nil for a result that is not on this page.
    init?(entry id: String)
}

/// The tabs heading a settings page. A search result chosen for the page opens the tab that holds it.
struct SettingsTabs<Tab: SettingsTab>: View {
    @Binding var selection: Tab
    @Environment(SearchModel.self) private var search: SearchModel?

    var body: some View {
        // In a section header, so the grouped form gives the tabs no card.
        ThawSection {
            ThawTabStrip(selection: $selection, tabs: Tab.allCases)
        } content: {
            EmptyView()
        }
        .task(id: search?.requestedEntry) {
            guard let search, let entry = SettingsSearchNavigation.consumeEntry(search: search), let holder = Tab(entry: entry) else { return }
            selection = holder
        }
    }
}
