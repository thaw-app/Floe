//
//  SearchViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Thaw 3's settings search views (Settings/Search/SearchViews.swift), plus the parts of its
//  Settings/SettingsView.swift that host them: the search field with its ⌘F shortcut and the
//  results that take over the detail column. The scroll to a chosen result, the field's
//  place above the sidebar, and the page header over the results are Floe's.

import SwiftUI
import ThawUI

// MARK: - SettingsSearchField

/// Puts the search field in the settings window and shares the model with the panes.
private struct SettingsSearchField: ViewModifier {
    @Bindable var search: SearchModel

    /// Whether the search field has focus. Driven by ⌘F; the system clears it on Escape or
    /// when the field loses focus.
    @State private var isSearchPresented = false

    func body(content: Content) -> some View {
        content
            // At the top of the sidebar, since the window has no toolbar. Applications and the
            // Extension Store filter their own lists with fields of their own.
            .searchable(
                text: $search.searchText,
                isPresented: $isSearchPresented,
                placement: .sidebar,
                prompt: Text(String(localized: "Search settings", bundle: .floe, comment: "The placeholder of the search field in the settings sidebar."))
            )
            .background {
                // ⌘F from anywhere in the window lands in the field.
                Button("Find") {
                    isSearchPresented = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
            }
            .environment(search)
    }
}

extension View {
    /// Adds the settings search field to the split view it is applied to.
    func settingsSearchField(_ search: SearchModel) -> some View {
        modifier(SettingsSearchField(search: search))
    }

    /// Scrolls this pane to the search result that opened it. The target is the view whose id
    /// equals the entry's anchor.
    func settingsSearchAnchorScroll() -> some View {
        modifier(SettingsSearchAnchorScroll())
    }
}

// MARK: - SettingsSearchAnchorScroll

private struct SettingsSearchAnchorScroll: ViewModifier {
    @Environment(SearchModel.self) private var search: SearchModel?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                // Runs when the pane appears and again when a result on the same pane is chosen.
                .task(id: search?.requestedAnchor) {
                    guard let search, let anchor = SettingsSearchNavigation.consumeAnchor(search: search) else { return }
                    proxy.scrollTo(anchor, anchor: .top)
                }
        }
    }
}

// MARK: - SettingsSearchResults

/// Search results in the detail column, in place of the selected pane.
struct SettingsSearchResults: View {
    @Environment(SearchModel.self) private var search
    let selection: SettingsSelection
    /// What is searched, built when the search begins.
    let entries: () -> [SearchEntry]

    var body: some View {
        SearchResultsList(groups: search.displayedGroups) { entry in
            SettingsSearchNavigation.selectSearchResult(entry, selection: selection, search: search)
        } header: {
            SettingsPageHeader()
            if !search.displayedGroups.isEmpty {
                // A count makes a long list read as bounded, and tells the
                // reader whether narrowing the query is worth it.
                // The catalog holds the singular as a plural variation, which only a String reads from Floe's bundle.
                Text(String(localized: "\(search.resultCount) results", bundle: .floe, comment: "The placeholder is how many settings a search found."))
                    .font(ThawType.detail.weight(.medium))
                    .foregroundStyle(ThawInk.supporting)
                    .padding(.bottom, ThawSpacing.compact)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal, ThawSpacing.compact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if search.displayedGroups.isEmpty {
                SearchEmptyView(query: search.searchText)
            }
        }
        // The index is built here, when a search begins, so showing a pane never builds it.
        .onAppear { search.setEntries(entries()) }
    }
}

// MARK: - SearchResultsList

/// Scrollable, grouped search results for the settings window, under a header that scrolls with them.
struct SearchResultsList<Header: View>: View {
    let groups: [SearchGroup]
    let onSelect: (SearchEntry) -> Void
    @ViewBuilder let header: Header

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                }
                // Where a form puts its page header, less the list's own margins.
                .padding(.horizontal, SettingsPageHeading.leadingMargin - ThawSpacing.compact - ThawSpacing.row)
                .padding(.top, SettingsPageHeading.topMargin)
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider()
                            .opacity(0.45)
                            .padding(.horizontal, ThawSpacing.compact)
                            .padding(.vertical, ThawSpacing.base)
                    }

                    SearchGroupSection(group: group, onSelect: onSelect)
                }
            }
            .padding(.horizontal, ThawSpacing.row)
            .padding(.bottom, ThawSpacing.inset)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - SearchGroupSection

private struct SearchGroupSection: View {
    let group: SearchGroup
    let onSelect: (SearchEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.tight) {
            HStack(spacing: ThawSpacing.compact) {
                // The same glyph the sidebar row shows, so a result group
                // names its pane the way the sidebar does.
                Group {
                    if let symbol = group.label.symbol {
                        Image(systemName: symbol)
                            .font(ThawType.symbol.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        IconView(value: group.label.icon, assetsPath: group.label.assetsPath, size: 16)
                    }
                }
                .frame(width: 18, height: 16)

                Text(group.label.title)
                    .font(ThawType.detail.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ThawSpacing.compact)
            .padding(.vertical, ThawSpacing.tight)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: ThawSpacing.hairline) {
                ForEach(group.entries) { entry in
                    SearchResultButton(entry: entry) {
                        onSelect(entry)
                    }
                }
            }
        }
    }
}

// MARK: - SearchResultRowAppearance

private enum SearchResultRowAppearance {
    static let shape = RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
}

// MARK: - SearchResultButton

/// Interactive search result row with hover and pressed feedback.
private struct SearchResultButton: View {
    let entry: SearchEntry
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            SearchResultRowContent(
                entry: entry,
                isHovering: isHovering
            )
        }
        .buttonStyle(
            SearchResultButtonStyle(
                isHovering: isHovering,
                rowShape: SearchResultRowAppearance.shape
            )
        )
        .onHover { isHovering = $0 }
        .thawAnimation(ThawMotion.quick, value: isHovering)
    }
}

// MARK: - SearchResultRowContent

private struct SearchResultRowContent: View {
    let entry: SearchEntry
    let isHovering: Bool

    var body: some View {
        HStack(alignment: .center, spacing: ThawSpacing.base) {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                Text(entry.title)
                    .font(ThawType.body.weight(isHovering ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                // Section says where the row lives, description what it does.
                if let section = entry.section {
                    Text(section)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let descriptionText = entry.descriptionText {
                    Text(descriptionText)
                        .font(.caption)
                        // .tertiary (~25% alpha) fails the text contrast floor.
                        .foregroundStyle(ThawInk.supporting)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(ThawType.micro.weight(.semibold))
                // Vibrancy tiers rather than a hand-set opacity, so the
                // chevron adapts to whatever is behind the glass.
                .foregroundStyle(isHovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .offset(x: isHovering ? 1 : 0)
        }
        .padding(.horizontal, ThawSpacing.row)
        .padding(.vertical, ThawSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(SearchResultRowAppearance.shape)
    }
}

// MARK: - SearchResultButtonStyle

private struct SearchResultButtonStyle: ButtonStyle {
    let isHovering: Bool
    let rowShape: RoundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                // Same selection wash as the sidebar pill, stronger on press.
                if let strength = strength(isPressed: configuration.isPressed) {
                    Color.clear
                        .thawGlass(.selection(.accentColor, strength: strength), in: rowShape)
                }
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
            .thawAnimation(ThawMotion.instant, value: configuration.isPressed)
    }

    private func strength(isPressed: Bool) -> ThawGlass.SelectionStrength? {
        if isPressed {
            return .selected
        }
        return isHovering ? .hover : nil
    }
}

// MARK: - SearchEmptyView

/// Empty state shown when a query returns no matches.
struct SearchEmptyView: View {
    /// The query that came up empty, quoted back so the reader can see
    /// what was actually searched, typos included.
    var query: String = ""

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        ThawEmptyState(
            systemImage: "magnifyingglass",
            title: trimmed.isEmpty ? "No settings found" : "No settings match “\(trimmed)”",
            caption: "Try a shorter or broader term."
        )
    }
}
