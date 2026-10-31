//
//  MenuItemSearchView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The front app's menu commands, in the launcher's own field, rows and bottom bar.
struct MenuItemSearchView: View {
    @ObservedObject var search: MenuItemSearchModel
    /// For the gear. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    let focusToken: Int

    var body: some View {
        PanelSections {
            SearchBar(placeholder: placeholder, text: $search.query, focusToken: focusToken, isLoading: search.isScanning) { EmptyView() }
        } content: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
    }

    private var placeholder: String {
        if let name = search.target?.name, !name.isEmpty {
            return String(localized: "Search the menus of \(name)…", bundle: .floe, comment: "The placeholder is the name of an app.")
        }
        return String(localized: "Search menu items…", bundle: .floe)
    }

    // MARK: Content

    /// Either the matching rows or the state that explains why there are none.
    @ViewBuilder
    private var content: some View {
        let hasQuery = !search.query.trimmingCharacters(in: .whitespaces).isEmpty
        if !search.accessGranted {
            ThawEmptyState(
                systemImage: "hand.raised",
                title: "Accessibility is off",
                caption: "Floe needs Accessibility to read the menus of the app in front.",
                actionTitle: "Grant Access",
                action: { search.requestAccess() }
            )
        } else if search.target == nil {
            ThawEmptyState(
                systemImage: "filemenu.and.selection",
                title: "No app in front",
                caption: "Open the launcher from an app to search its menus."
            )
        } else if search.isScanning, search.results.isEmpty {
            ThawEmptyState(systemImage: "filemenu.and.selection", title: "Reading the menus…", isLoading: true)
        } else if hasQuery, search.results.isEmpty {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No menu items match",
                caption: "Try part of the command's name or the menu it is in."
            )
        } else if search.results.isEmpty {
            ThawEmptyState(
                systemImage: "filemenu.and.selection",
                title: "No menu items found",
                caption: "This app has no menu commands Floe can choose."
            )
        } else {
            rows
        }
    }

    private var rows: some View {
        let results = search.results
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        MenuItemRowView(entry: entry, appURL: search.target?.url, selected: index == search.selection)
                            .onTapGesture(count: 2) { search.choose(entry) }
                            .onTapGesture { search.selection = index }
                            .id(entry.id)
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .onChange(of: search.selection) {
                if results.indices.contains(search.selection) {
                    proxy.scrollTo(results[search.selection].id)
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        PanelBottomBar {
            OpenSettingsButton(model: launcher)
            Spacer(minLength: 0)
            if let entry = search.selectedEntry {
                ShortcutHintButton(title: MenuItemRows.chooseTitle) { search.choose(entry) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
    }
}

/// One menu command: the app's icon, the command's title, and at the right the menus it is in and its shortcut,
/// so the row is one line high like every other in the panel.
struct MenuItemRowView: View {
    let entry: AppMenuItem
    let appURL: URL?
    let selected: Bool

    var body: some View {
        PaletteRow(title: entry.title, subtitle: nil, selected: selected) {
            if let appURL {
                AppIconView(path: appURL.path, size: 24)
            } else {
                SymbolTile(symbol: "filemenu.and.selection")
            }
        } trailing: {
            if !entry.menuPath.isEmpty {
                // The end of a long path is the menu the command is in, which says the most.
                Text(verbatim: entry.menuPath)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if let shortcut = entry.shortcut {
                Text(verbatim: shortcut.label)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
