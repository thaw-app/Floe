//
//  SettingsSidebarPaneList.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The settings sidebar: plain symbols, small uppercase headings between the groups, and a soft gray
/// fill on the selected row. The pieces are `ListStyle`'s, which the rest of the app's lists share.
///
/// Rows of its own, not a List: a List draws its own selection over this one, and its Sections crash
/// AppKit on macOS 27.0 and 27.2. Once the sidebar has focus, the arrow keys move as in a list.
struct SettingsSidebarPaneList: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    static let listWidth: CGFloat = 220

    @Environment(SearchModel.self) private var search
    @FocusState private var isFocused: Bool

    private var rows: [SettingsSidebarRow] {
        SettingsSidebarRows.rows(commands: catalog.allCommands, disabledExtensions: settings.disabledExtensions)
    }

    /// No row is selected during a search, so a click on any row, the current pane's included, ends it.
    private var selectedPage: SettingsPage? {
        search.isSearching ? nil : selection.page
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                    ForEach(rows) { row in
                        switch row {
                        case let .heading(title):
                            ListSectionHeading(title: title)
                        case let .page(page):
                            SettingsSidebarPageRow(row: page, isSelected: page.page == selectedPage, showsFocus: isFocused) {
                                SettingsSearchNavigation.selectSidebarPane(page.page, selection: selection, search: search)
                            }
                        }
                    }
                }
                .padding(.horizontal, ThawSpacing.row)
                .padding(.vertical, ThawSpacing.base)
            }
            // A page chosen by the arrow keys, a search result or the launcher stays in sight.
            // A page's row has the page's id.
            .onChange(of: selection.page) { proxy.scrollTo(selection.page.id) }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .thawKeyboardList(isFocused: $isFocused) { direction in
            switch direction {
            case .up: move(by: -1)
            case .down: move(by: 1)
            default: break
            }
        }
    }

    /// Selects the page above or below the selected one, past the headings.
    private func move(by offset: Int) {
        if let next = rows.compactMap(\.page).item(stepping: offset, from: { $0 == selection.page }) {
            SettingsSearchNavigation.selectSidebarPane(next, selection: selection, search: search)
        }
    }
}

/// A page's row: its symbol, or an extension's own icon, in the shared box, and its name, with the sidebar's
/// selected fill. A disabled extension's row reads as off.
private struct SettingsSidebarPageRow: View {
    let row: SettingsSidebarPage
    let isSelected: Bool
    /// The sidebar has keyboard focus, so the selected row shows the focus ring.
    let showsFocus: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label {
                Text(row.label.title)
                    .font(ThawType.body)
                    .foregroundStyle(row.isDimmed ? Color.secondary : Color.primary)
                    .lineLimit(1)
            } icon: {
                ListRowIcon(source: row.label.symbol.map { .symbol($0) } ?? .icon(row.label.icon, assetsPath: row.label.assetsPath), isDimmed: row.isDimmed && row.label.symbol == nil)
            }
            .padding(.horizontal, ThawSpacing.row)
            .frame(maxWidth: .infinity, minHeight: ListStyle.rowHeight, alignment: .leading)
            .selectedRowBackground(isSelected)
        }
        .buttonStyle(.plain)
        .thawFocusRing(isSelected && showsFocus, in: ListStyle.rowShape)
    }
}
