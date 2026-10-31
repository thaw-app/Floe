//
//  SettingsSidebarPaneList.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The shared sidebar. No row is selected during a search, so a click on any row, even the current pane's, ends it.
struct SettingsSidebarPaneList: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    @Environment(SearchModel.self) private var search

    var body: some View {
        let rows = SettingsSidebarRows.rows(commands: catalog.allCommands, disabledExtensions: settings.disabledExtensions)
        let pages = rows.pagesByID
        ThawSidebar(
            rows: rows.map(\.sidebarRow),
            current: selection.page,
            showsSelection: !search.isSearching,
            select: { SettingsSearchNavigation.selectSidebarPane($0, selection: selection, search: search) },
            title: { Text(pages[$0]?.label.title ?? "") },
            isDimmed: { pages[$0]?.isDimmed ?? false },
            icon: { page in
                if let label = pages[page]?.label {
                    if let symbol = label.symbol {
                        ListRowIcon(source: .symbol(symbol))
                    } else {
                        // An extension's own icon keeps its colour, which the sidebar's would otherwise take over.
                        ListRowIcon(source: .icon(label.icon, assetsPath: label.assetsPath))
                            .foregroundStyle(.primary)
                    }
                }
            }
        )
    }
}

extension SettingsSidebarRow {
    var sidebarRow: ThawSidebarRow<SettingsPage> {
        switch self {
        case let .heading(title): .heading(title)
        case let .page(row): .page(row.page)
        }
    }
}

extension [SettingsSidebarRow] {
    /// Each row's name and icon, for the shared sidebar to look up by page.
    var pagesByID: [SettingsPage: SettingsSidebarPage] {
        reduce(into: [:]) { pages, row in
            if case let .page(page) = row {
                pages[page.page] = page
            }
        }
    }
}
