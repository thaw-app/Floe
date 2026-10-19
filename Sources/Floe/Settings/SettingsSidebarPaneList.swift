//
//  SettingsSidebarPaneList.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The settings sidebar: plain symbols, small uppercase headings between the groups, and a soft gray
/// fill on the selected row.
///
/// Rows of its own, not a List: a List draws its own selection over this one, and its Sections crash
/// AppKit on macOS 27.0 and 27.2. Once the sidebar has focus, the arrow keys move as in a list.
struct SettingsSidebarPaneList: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    static let listWidth: CGFloat = 220

    @Environment(SearchModel.self) private var search

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
                            SettingsSidebarHeading(title: title)
                        case let .page(page):
                            SettingsSidebarPageRow(row: page, isSelected: page.page == selectedPage) {
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
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .up: move(by: -1)
            case .down: move(by: 1)
            default: break
            }
        }
    }

    /// Selects the page above or below the selected one, past the headings.
    private func move(by offset: Int) {
        let pages = rows.compactMap(\.page)
        guard let current = pages.firstIndex(of: selection.page) else { return }
        let next = current + offset
        guard pages.indices.contains(next) else { return }
        SettingsSearchNavigation.selectSidebarPane(pages[next], selection: selection, search: search)
    }
}

/// The small uppercase name over a group of pages.
private struct SettingsSidebarHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            // Room above each group, so the groups read apart.
            .padding(.top, ThawSpacing.gutter)
            .padding(.bottom, ThawSpacing.tight)
            .padding(.leading, ThawSpacing.row)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A page's row: its symbol, or an extension's own icon at the symbol's size, and its name, on a
/// light gray fill with a faint edge when selected. The fill is the same whether the window is
/// key or not, and the label keeps its own color on it.
private struct SettingsSidebarPageRow: View {
    let row: SettingsSidebarPage
    let isSelected: Bool
    let select: () -> Void

    /// The box the icons share, so the names line up; an extension's icon is a little smaller
    /// than it, to weigh the same as a symbol.
    private static let iconBox: CGFloat = 18
    private static let height: CGFloat = 32
    private static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        Button(action: select) {
            Label {
                Text(row.label.title)
                    .font(ThawType.body)
                    .foregroundStyle(row.isDimmed ? Color.secondary : Color.primary)
                    .lineLimit(1)
            } icon: {
                Group {
                    if let symbol = row.label.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                    } else {
                        IconView(value: row.label.icon, assetsPath: row.label.assetsPath, size: 16)
                            .opacity(row.isDimmed ? 0.5 : 1)
                    }
                }
                .frame(width: Self.iconBox, height: Self.iconBox)
            }
            .padding(.horizontal, ThawSpacing.row)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .background {
                if isSelected {
                    Self.shape
                        .fill(Color.primary.opacity(0.1))
                        .overlay(Self.shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                }
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
