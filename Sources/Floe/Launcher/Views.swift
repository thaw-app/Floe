//
//  Views.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Clear space between the glass and the window's edge. The window casts no shadow of its own,
    /// because AppKit outlines the window's rectangle and that shows as square corners behind the
    /// rounded glass; the margin leaves the glass room to draw its own depth.
    static let margin: CGFloat = 40

    var body: some View {
        let state = model.panelState
        let size = state.contentSize(in: settings.launcherLayout)
        let look = settings.launcherLook(for: colorScheme)
        let heights = state.pieceHeights(in: settings.launcherLayout)
        GlassEffectContainer {
            if let setup = model.setup {
                SetupView(form: model.setupForm, request: setup).modifier(PanelOnePiece())
            } else if let session = model.session, session.command.mode == "view" {
                SessionContainer(model: model, session: session)
            } else if model.isSearchingMenuBar {
                MenuBarSearchView(search: model.menuBarSearch, launcher: model, focusToken: model.focusToken)
            } else if model.isShowingClipboardHistory {
                ClipboardHistoryView(clipboard: model.clipboardHistory, launcher: model, focusToken: model.focusToken)
            } else if model.isSearchingFiles {
                FileSearchView(search: model.fileSearch, spotlight: model.fileSearch.spotlight, launcher: model, focusToken: model.focusToken)
            } else if let asking = model.askAI {
                AskAIView(launcher: model, asking: asking)
            } else {
                RootView(model: model, isCollapsed: state.isCollapsed(in: settings.launcherLayout))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.searchFieldShape, settings.searchFieldShape)
        .modifier(PanelLook(look: look, pieces: settings.separatesSearchField ? PanelPieces(look: look, fieldShape: settings.searchFieldShape, heights: heights) : nil))
        .padding(Self.margin)
        // The window is resized a moment before or after the content: the search bar stays at the top meanwhile.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: Shared chrome

struct SearchBar<Accessory: View>: View {
    let placeholder: String
    @Binding var text: String
    let focusToken: Int
    var isLoading = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        SearchQueryField(prompt: placeholder, text: $text, focusToken: focusToken, isLoading: isLoading) { accessory }
    }
}

struct RowBackground: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ThawSpacing.row)
            .frame(height: 38)
            .modifier(SearchRowBackground(selected: selected))
    }
}

struct Footer<Leading: View>: View {
    var primary: String?
    var primaryKey = "↵"
    var hasActions = false
    @ViewBuilder var leading: Leading

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                leading
                Spacer()
                if let primary {
                    Text(primary).fontWeight(.medium)
                    KeyCap(primaryKey)
                }
                if hasActions {
                    Divider().frame(height: 14)
                    Text("Actions").foregroundStyle(.secondary)
                    KeyCap("⌘K")
                }
            }
            .font(ThawType.footnote)
            .padding(.horizontal, ThawSpacing.gutter)
            .frame(height: 38)
        }
    }
}

struct KeyCap: View {
    let label: String
    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        KeyCapView(text: label, font: ThawType.caption.weight(.medium))
    }
}

// MARK: Root search

struct RootView: View {
    @ObservedObject var model: LauncherModel
    var isCollapsed = false

    var body: some View {
        let results = model.results
        PanelSections(showsContent: !isCollapsed) {
            SearchBar(placeholder: String(localized: "Search apps and commands…", bundle: .floe), text: $model.query, focusToken: model.focusToken, isLoading: model.isLoadingCatalog || model.isAwaitingResults) { EmptyView() }
        } content: {
            if results.isEmpty, !model.isLoadingCatalog, !model.isAwaitingResults {
                ThawEmptyState(
                    systemImage: "magnifyingglass",
                    title: .verbatim(model.activeScope?.scope.emptyTitle ?? String(localized: "Nothing matches", bundle: .floe)),
                    caption: model.activeScope == nil ? "Try part of an app's or a command's name, or an alias." : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RootResultList(model: model, results: results)
                    .equatable()
            }
            bottomBar(results: results)
        }
    }

    /// The Thaw-style bottom bar: settings on the left, the selected row's
    /// actions with their key equivalents on the right.
    private func bottomBar(results: [RootResult]) -> some View {
        PanelBottomBar {
            OpenSettingsButton(model: model)

            Spacer(minLength: 0)

            if let selected = results.indices.contains(model.selection) ? results[model.selection].item : nil {
                if !selected.isScopeResult {
                    ShortcutHintButton(title: String(localized: "Favorite", bundle: .floe, comment: "A verb on a button: add the selected result to the favorites.")) { model.toggleFavorite(selected) } hint: {
                        KeyCapView(text: "⌘")
                        Text(verbatim: "+")
                        KeyCapView(text: "⇧")
                        KeyCapView(text: "F")
                    }
                }
                ShellHintButtons(model: model, action: selected.shellAction)
                ActionsButton(model: model) { $0.selectedRootItem.map($0.rootActions) ?? [] }
                ShortcutHintButton(title: model.primaryActionTitle(for: selected)) { model.activate(selected) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
    }
}

/// The keys a row of the shell answers to besides Return, in the bottom bar.
struct ShellHintButtons: View {
    let model: LauncherModel
    let action: ShellAction?

    var body: some View {
        switch action {
        case let .run(command, terminal):
            ShortcutHintButton(title: String(localized: "Output", bundle: .floe, comment: "A button that runs a command and shows what it printed.")) {
                model.runShellCommand(command, terminal: terminal, showingOutput: true)
            } hint: {
                KeyCapView(text: "⌥")
                KeyCapView(systemImage: "return")
            }
        case let .complete(row):
            ShortcutHintButton(title: ShellAction.complete(row).title) { model.complete(with: row) } hint: {
                KeyCapView(text: "⇥")
            }
        case .quit, nil:
            EmptyView()
        }
    }
}

struct SectionTitle: View {
    let title: String
    var isFirst = false

    var body: some View {
        SearchSectionHeader(title: title)
    }
}

/// One result. Equatable so a new list of results redraws the rows that changed, not every row on screen.
struct RootRow: View, Equatable {
    let item: RootItem
    let selected: Bool
    let matched: [Int]
    let isInMenuBar: Bool
    let isFavorite: Bool
    let alias: String?

    init(model: LauncherModel, item: RootItem, selected: Bool) {
        self.item = item
        self.selected = selected
        if case let .file(file) = item, !file.matched.isEmpty {
            // The index matched the name itself, also when the query began with a scope's word.
            matched = file.matched
        } else {
            matched = Fuzzy.match(model.searchedQuery, item.title)?.matched ?? []
        }
        if case let .command(command) = item {
            isInMenuBar = model.isInMenuBar(command)
        } else {
            isInMenuBar = false
        }
        isFavorite = model.isFavorite(item)
        alias = model.alias(for: item)
    }

    static func == (lhs: RootRow, rhs: RootRow) -> Bool {
        lhs.item.id == rhs.item.id && lhs.item.title == rhs.item.title && lhs.item.rowLabel == rhs.item.rowLabel
            && lhs.selected == rhs.selected && lhs.matched == rhs.matched && lhs.isInMenuBar == rhs.isInMenuBar
            && lhs.isFavorite == rhs.isFavorite && lhs.alias == rhs.alias
    }

    var body: some View {
        PaletteRow(title: item.title, subtitle: nil, selected: selected, matched: matched) {
            RootIcon(item: item)
        } trailing: {
            HStack(spacing: ThawSpacing.compact) {
                // Raycast-style: the kind sits on the row's right edge instead
                // of a second line, so the name uses the full width.
                Text(item.rowLabel)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isInMenuBar {
                    Image(systemName: "checkmark").font(ThawType.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("In the menu bar")
                }
                if isFavorite {
                    Image(systemName: "star.fill").font(ThawType.caption).foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                if let alias {
                    KeyCap(alias)
                }
            }
        }
    }
}
