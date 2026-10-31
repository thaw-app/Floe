//
//  SettingsSidebarPaneList.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The shared settings sidebar, on Floe's soft gray selection rather than the accent colour. No row is selected
/// during a search, so a click on any row, the current pane's included, ends it.
struct SettingsSidebarPaneList: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    static let listWidth: CGFloat = 220
    static let colors = ThawSidebarColors(selection: .flat(fill: .primary.opacity(0.1), edge: .primary.opacity(0.08)))

    @Environment(SearchModel.self) private var search

    var body: some View {
        let rows = SettingsSidebarRows.rows(commands: catalog.allCommands, disabledExtensions: settings.disabledExtensions)
        let pages = rows.pagesByID
        ThawSidebar(
            rows: rows.map(\.sidebarRow),
            current: selection.page,
            showsSelection: !search.isSearching,
            colors: Self.colors,
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
    /// What the shared sidebar draws for this row.
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
