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
                SetupView(form: model.setupForm, request: setup, submit: model.submitSetup, cancel: model.cancelSetup).modifier(PanelOnePiece())
            } else if let session = model.runner.session, session.command.mode == "view" {
                SessionContainer(model: model, session: session)
            } else if model.isSearchingMenuBar {
                MenuBarSearchView(search: model.menuBarSearch, launcher: model, focusToken: model.focusToken)
            } else if let menuItems = model.menuItemSearch {
                MenuItemSearchView(search: menuItems, launcher: model, focusToken: model.focusToken)
            } else if model.isShowingClipboardHistory {
                ClipboardHistoryView(clipboard: model.clipboardHistory, launcher: model, focusToken: model.focusToken, history: model.clipboard)
            } else if model.isSearchingFiles {
                FileSearchView(search: model.fileSearch, spotlight: model.fileSearch.spotlight, launcher: model, focusToken: model.focusToken)
            } else if let desk = model.noteDesk {
                NoteDeskView(desk: desk, launcher: model, focusToken: model.focusToken)
            } else if let asking = model.askAI {
                AskAIView(launcher: model, asking: asking)
            } else {
                RootView(model: model, refusal: model.refusal, isCollapsed: state.isCollapsed(in: settings.launcherLayout))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .overlay {
            if let question = model.question {
                PanelQuestionCard(
                    title: question.title,
                    message: question.detail,
                    primaryTitle: question.button,
                    dismissTitle: String(localized: "Cancel", bundle: .floe),
                    isDestructive: true
                ) { model.answer(question, yes: $0) }
            }
        }
        .environment(\.searchFieldCorners, settings.searchFieldCorners)
        .environment(\.searchFieldBeam, settings.searchFieldBeam)
        .environment(\.searchFieldBeamFrameRate, settings.searchFieldBeamFrameRate)
        .environment(\.pointerRest, model.pointerRest)
        .modifier(PanelLook(look: look, pieces: settings.separatesSearchField ? PanelPieces(look: look, corners: settings.searchFieldCorners, heights: heights) : nil))
        .modifier(RefusalShake(refusal: model.refusal))
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
    var isRefused = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        SearchQueryField(prompt: placeholder, text: $text, focusToken: focusToken, isLoading: isLoading, isRefused: isRefused) { accessory }
    }
}

struct RowBackground: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ThawSpacing.row)
            .frame(height: PanelRow.height)
            .modifier(SearchRowBackground(selected: selected))
    }
}

/// The bar under an extension's view, its setup and its error. It is `PanelBottomBar`, so it reads as every other
/// mode's: what is on the left, then the primary action and Actions as buttons with their keys.
struct Footer<Leading: View>: View {
    var primary: String?
    /// Whether the primary action takes ⌘ with Return, as a form's does.
    var primaryTakesCommand = false
    var runPrimary: () -> Void = {
        // Nothing to run.
    }

    /// Opens the Actions menu. Nil when there is no action besides the primary one.
    var showActions: (() -> Void)?
    @ViewBuilder var leading: Leading

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            PanelBottomBar {
                leading
                Spacer(minLength: 0)
                if let primary {
                    ShortcutHintButton(title: primary, action: runPrimary) {
                        if primaryTakesCommand {
                            KeyCapView(text: "⌘")
                        }
                        KeyCapView(systemImage: "return")
                    }
                }
                if let showActions {
                    ShortcutHintButton(title: String(localized: "Actions…", bundle: .floe), action: showActions) {
                        KeyCapView(text: "⌘")
                        KeyCapView(text: "K")
                    }
                }
            }
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
    @ObservedObject var refusal: ReturnRefusal
    var isCollapsed = false

    var body: some View {
        let results = model.results
        PanelSections(showsContent: !isCollapsed) {
            SearchBar(placeholder: String(localized: "Search apps and commands…", bundle: .floe), text: $model.query, focusToken: model.focusToken, isLoading: model.catalog.isLoading || model.isAwaitingResults, isRefused: refusal.isShown) { EmptyView() }
        } content: {
            if results.isEmpty, !model.catalog.isLoading, !model.isAwaitingResults {
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
                // Where the menu offers Favorites, with the keys its row has.
                if LauncherModel.keepsItsPlace(selected), let keys = model.rowKeys(for: selected).key(for: .toggleFavorite) {
                    ShortcutHintButton(title: String(localized: "Favorite", bundle: .floe, comment: "A verb on a button: add the selected result to the favorites.")) { model.toggleFavorite(selected) } hint: {
                        KeyCaps(keys: keys)
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
                model.features.shell.runShellCommand(command, terminal: terminal, showingOutput: true)
            } hint: {
                KeyCapView(text: "⌥")
                KeyCapView(systemImage: "return")
            }
        case let .complete(row):
            ShortcutHintButton(title: ShellAction.complete(row).title) { model.features.shell.complete(with: row) } hint: {
                KeyCapView(text: "⇥")
            }
        case .quit, nil:
            EmptyView()
        }
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
