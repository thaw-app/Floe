//
//  MenuBarSearchView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The menu bar search: the launcher's own field, rows and bottom bar, so the panel reads the same in every mode.
struct MenuBarSearchView: View {
    @ObservedObject var search: MenuBarSearchModel
    /// For the gear and the Actions menu. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    let focusToken: Int
    @ObservedObject var settings: AppSettings = .shared

    var body: some View {
        PanelSections {
            SearchBar(placeholder: String(localized: "Search menu bar items…", bundle: .floe), text: $search.query, focusToken: focusToken, isLoading: search.isScanning) { EmptyView() }
        } content: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
    }

    // MARK: Content

    /// Either the matching rows or the state that explains why there are none.
    @ViewBuilder
    private var content: some View {
        let hasQuery = !search.query.trimmingCharacters(in: .whitespaces).isEmpty
        if !search.accessGranted {
            // Distinct from "nothing matched": without Accessibility the walk returns an empty list.
            ThawEmptyState(
                systemImage: "hand.raised",
                title: "Accessibility is off",
                caption: "Floe needs Accessibility to list your menu bar items.",
                actionTitle: "Grant Access",
                action: { search.requestAccess() }
            )
        } else if search.isScanning, search.results.isEmpty {
            ThawEmptyState(systemImage: "menubar.rectangle", title: "Reading your menu bar…", isLoading: true)
        } else if hasQuery, search.results.isEmpty {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No items match",
                caption: "Try part of the item's name or the app that owns it."
            )
        } else if search.results.isEmpty {
            ThawEmptyState(
                systemImage: "menubar.rectangle",
                title: "No menu bar items found",
                caption: "Floe lists the items apps put in the menu bar."
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
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        // One view per item, title included: a lazy stack walks the whole list when rows vary in count.
                        VStack(alignment: .leading, spacing: 0) {
                            if let section = result.section, index == 0 || results[index - 1].section != section {
                                ListSectionHeading(title: section, isFirst: index == 0)
                            }
                            MenuBarItemRow(
                                extra: result.extra,
                                name: search.displayName(for: result.extra),
                                selected: index == search.selection,
                                renameDraft: search.renamingItem == result.extra.id ? $search.renameDraft : nil
                            )
                            .onTapGesture(count: 2) { search.open(result.extra) }
                            .onTapGesture { search.selection = index }
                        }
                        .id(result.id)
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

            Toggle("Remember last search", isOn: $settings.rememberMenuBarQuery)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()

            Spacer(minLength: 0)

            if search.renamingItem != nil {
                ShortcutHintButton(title: String(localized: "Cancel", bundle: .floe)) { search.cancelRename() } hint: {
                    KeyCapView(text: "esc")
                }
                ShortcutHintButton(title: String(localized: "Rename", bundle: .floe, comment: "A button that saves the new name of a menu bar item.")) { search.commitRename() } hint: {
                    KeyCapView(systemImage: "return")
                }
            } else if let extra = search.selectedExtra {
                ShortcutHintButton(title: String(localized: "Edit Name", bundle: .floe)) { search.beginRenamingSelection() } hint: {
                    KeyCapView(text: "⌘")
                    KeyCapView(text: "E")
                }
                ActionsButton(model: launcher) { $0.menuBarSearch.selectedExtra.map($0.menuBarSearch.actions) ?? [] }
                ShortcutHintButton(title: String(localized: "Click Item", bundle: .floe, comment: "A button that clicks the selected menu bar item.")) { search.open(extra) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
    }
}

/// One menu bar item, drawn as every result is: its app's icon, its name, and the app that owns it at the right.
struct MenuBarItemRow: View {
    let extra: MenuBarExtra
    let name: String
    let selected: Bool
    /// Set while this row is being renamed; the field takes the title's place.
    var renameDraft: Binding<String>?
    @FocusState private var isEditing: Bool

    var body: some View {
        if let renameDraft {
            // The same measures as PaletteRow, which has no field of its own.
            HStack(spacing: PanelRow.iconSpacing) {
                icon.frame(width: PanelRow.iconBox, height: PanelRow.iconBox)
                TextField(extra.name, text: renameDraft)
                    .textFieldStyle(.plain)
                    .font(ThawType.body)
                    .autocorrectionDisabled(true)
                    .focused($isEditing)
                    .onAppear { isEditing = true }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PanelRow.inset)
            .frame(minHeight: PanelRow.height)
            .modifier(SearchRowBackground(selected: selected))
        } else {
            PaletteRow(title: name, subtitle: nil, selected: selected) {
                icon
            } trailing: {
                if extra.ownerName != name {
                    Text(verbatim: extra.ownerName)
                        .font(ThawType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var icon: some View {
        if let owner = extra.ownerURL {
            AppIconView(path: owner.path, size: 24)
        } else {
            SymbolTile(symbol: "menubar.rectangle")
        }
    }
}
