//
//  SettingsSidebarPaneList.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Thaw 3's settings sidebar: a standard source list, so selection, keyboard and VoiceOver
/// come from AppKit rather than from hand-drawn rows.
struct SettingsSidebarPaneList: View {
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    static let listWidth: CGFloat = 210

    /// Width of the icon column, so labels line up whatever each symbol's
    /// own width is.
    private static let iconColumn: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme
    @Environment(SearchModel.self) private var search

    /// The accent, deepened in dark mode so a light one such as yellow keeps
    /// its contrast against the selected label.
    private var accent: Color {
        colorScheme == .dark ? Color.accentColor.mix(with: .black, by: 0.4) : Color.accentColor
    }

    private nonisolated struct Row: Identifiable {
        let page: SettingsPage
        let title: String
        let symbol: String?
        let icon: String?
        let assetsPath: String
        var isDimmed = false
        var id: SettingsPage {
            page
        }
    }

    /// General and Applications first, then each extension, About last, as in Thaw.
    private var rows: [Row] {
        let extensions = catalog.allCommands
            .uniqued(on: \.extensionName)
            .sorted { $0.extensionTitle.localizedCaseInsensitiveCompare($1.extensionTitle) == .orderedAscending }
            .map { command in
                Row(
                    page: .extensionPage(command.extensionName),
                    title: command.extensionTitle,
                    symbol: nil,
                    icon: command.icon ?? "icon:Terminal",
                    assetsPath: command.assetsPath,
                    isDimmed: settings.disabledExtensions.contains(command.extensionName)
                )
            }
        return [
            Row(page: .general, title: SearchPaneLabel.general.title, symbol: "gearshape", icon: nil, assetsPath: ""),
            Row(page: .applications, title: SearchPaneLabel.applications.title, symbol: "square.grid.2x2", icon: nil, assetsPath: ""),
            Row(page: .quicklinks, title: SearchPaneLabel.quicklinks.title, symbol: "link", icon: nil, assetsPath: ""),
            Row(page: .snippets, title: SearchPaneLabel.snippets.title, symbol: "text.quote", icon: nil, assetsPath: ""),
            Row(page: .extensionStore, title: SearchPaneLabel.extensionStore.title, symbol: "bag", icon: nil, assetsPath: ""),
            Row(page: .appearance, title: SearchPaneLabel.appearance.title, symbol: "paintbrush", icon: nil, assetsPath: ""),
            Row(page: .privacy, title: SearchPaneLabel.privacy.title, symbol: "hand.raised", icon: nil, assetsPath: ""),
        ] + extensions + [
            Row(page: .about, title: SearchPaneLabel.about.title, symbol: "cube", icon: nil, assetsPath: ""),
        ]
    }

    var body: some View {
        // No Sections: an outline-backed list crashes AppKit on macOS 27.0 and 27.2
        // (freed row view in sizeLastColumnToFit).
        // No row is selected during a search, so a click on any row, the current pane's included, ends it.
        List(selection: Binding(
            get: { search.isSearching ? nil : selection.page },
            set: {
                if let page = $0 {
                    SettingsSearchNavigation.selectSidebarPane(page, selection: selection, search: search)
                }
            }
        )) {
            ForEach(rows) { row in
                Label {
                    Text(row.title)
                        .font(ThawType.detail.weight(.medium))
                        .foregroundStyle(row.isDimmed ? Color.secondary : Color.primary)
                        .lineLimit(1)
                } icon: {
                    Group {
                        if let symbol = row.symbol {
                            Image(systemName: symbol)
                                .font(ThawType.symbol.weight(.medium))
                                .foregroundStyle(Color.secondary)
                        } else {
                            IconView(value: row.icon, assetsPath: row.assetsPath, size: 16)
                                .opacity(row.isDimmed ? 0.5 : 1)
                        }
                    }
                    .frame(width: Self.iconColumn)
                }
                // Only the selection fill carries the accent. Applied per row,
                // where the sidebar reads it.
                .listItemTint(row.page == selection.page && !search.isSearching ? .preferred(accent) : .monochrome)
                .tag(row.page)
            }
        }
        .listStyle(.sidebar)
        // The selection fill uses the same deepened accent.
        .tint(accent)
        // Medium rows whatever the system's sidebar size: at Large the labels
        // and symbols crowd a settings window this narrow.
        .environment(\.sidebarRowSize, .medium)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, ThawSpacing.base, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
