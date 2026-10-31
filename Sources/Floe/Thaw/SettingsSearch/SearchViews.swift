//
//  SearchViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  What hosts ThawUI's settings search views on Floe's model: the search field in the sidebar, the
//  scroll to a chosen result, and the results that take over the detail column.

import SwiftUI
import ThawUI

// MARK: - SettingsSearchField

extension View {
    /// Adds the settings search field to the split view it is applied to.
    func settingsSearchField(_ search: SearchModel, selection: SettingsSelection) -> some View {
        modifier(FloeSettingsSearchField(search: search, selection: selection))
    }

    /// Scrolls this pane to the search result that opened it. The target is the view whose id
    /// equals the entry's anchor.
    func settingsSearchAnchorScroll() -> some View {
        modifier(SettingsSearchAnchorScroll())
    }
}

/// The shared search field on Floe's model: at the top of the sidebar, so the toolbar only names the page. Applications
/// and the Extension Store filter their own lists with fields of their own.
private struct FloeSettingsSearchField: ViewModifier {
    @Bindable var search: SearchModel
    let selection: SettingsSelection

    func body(content: Content) -> some View {
        content
            .settingsSearchField(
                text: $search.searchText,
                placement: .sidebar,
                prompt: LocalizedStringResource("Search settings", bundle: .floe, comment: "The placeholder of the search field in the settings sidebar."),
                findLabel: "Find",
                keyboard: SettingsSearchKeyboard(
                    isSearching: search.isSearching,
                    previousLabel: "Previous Result",
                    nextLabel: "Next Result",
                    move: { search.moveHighlight(by: $0) },
                    submit: {
                        // Return opens the result the arrows are on, the first until they move.
                        if let entry = search.highlightedEntry {
                            SettingsSearchNavigation.selectSearchResult(entry, selection: selection, search: search)
                        }
                    }
                )
            )
            .environment(search)
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

/// Search results in the detail column, in place of the selected pane. No page title: the sidebar's search field
/// already says what this is.
struct SettingsSearchResults: View {
    @Environment(SearchModel.self) private var search
    let selection: SettingsSelection
    /// What is searched, built when the search begins.
    let entries: () -> [SearchEntry]

    var body: some View {
        SearchResultsList(groups: search.displayedGroups, highlighted: search.highlighted) { entry in
            SettingsSearchNavigation.selectSearchResult(entry, selection: selection, search: search)
        } header: {
            if !search.displayedGroups.isEmpty {
                // The catalog holds the singular as a plural variation, which only a String reads from Floe's bundle.
                SettingsSearchResultCount(Text(String(localized: "\(search.resultCount) results", bundle: .floe, comment: "The placeholder is how many settings a search found.")))
                    .padding(.horizontal, SettingsPageHeading.leadingMargin - ThawSpacing.compact - ThawSpacing.row)
                    .padding(.top, SettingsPageHeading.topMargin)
                    .padding(.bottom, ThawSpacing.compact)
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

/// The shared results list on Floe's groups and entries, with the neutral hover the rest of Floe's rows have.
struct SearchResultsList<Header: View>: View {
    let groups: [SearchGroup]
    /// The result the arrow keys are on.
    var highlighted: String?
    let onSelect: (SearchEntry) -> Void
    @ViewBuilder let header: Header

    var body: some View {
        SettingsSearchResultsList(
            groups: groups,
            entries: \.entries,
            highlighted: highlighted,
            hoverTint: .primary,
            onSelect: onSelect,
            groupTitle: { Text($0.label.title) },
            result: { entry in
                SettingsSearchResultText(
                    title: Text(entry.title),
                    section: entry.section.map { Text($0) },
                    detail: entry.descriptionText.map { Text($0) }
                )
            },
            // The same glyph the sidebar row shows, so a result group names its pane the way the sidebar does.
            groupIcon: { group in
                ListRowIcon(source: group.label.symbol.map { .symbol($0) } ?? .icon(group.label.icon, assetsPath: group.label.assetsPath))
            },
            header: { header }
        )
    }
}

// MARK: - SearchEmptyView

/// Empty state shown when a query returns no matches.
struct SearchEmptyView: View {
    /// The query that came up empty, quoted back so the reader can see
    /// what was actually searched, typos included.
    var query: String = ""

    var body: some View {
        NoMatchesState(
            query: query,
            title: { "No settings match “\($0)”" },
            emptyQueryTitle: "No settings found",
            caption: "Try a shorter or broader term."
        )
    }
}
