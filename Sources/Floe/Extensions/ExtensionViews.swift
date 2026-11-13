//
//  ExtensionViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: Extension command

struct ExtensionView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var session: ExtensionSession

    var body: some View {
        let view = session.view
        let actions = session.actions
        ZStack {
            if view?.type == "Form" {
                // A form has a title where the others have a search field, so it stays one piece.
                VStack(spacing: 0) {
                    PanelHeader(
                        title: view?.string("navigationTitle") ?? session.command.title,
                        icon: session.command.icon,
                        assetsPath: session.command.assetsPath,
                        isLoading: view?.bool("isLoading") ?? false
                    )
                    content(view: view, actions: actions)
                }
                .modifier(PanelOnePiece())
            } else {
                PanelSections {
                    SearchBar(
                        placeholder: view?.string("searchBarPlaceholder") ?? (session.isList ? String(localized: "Search…", bundle: .floe) : session.command.title),
                        text: $session.searchText,
                        focusToken: model.focusToken,
                        isLoading: view?.bool("isLoading") ?? (view == nil)
                    ) {
                        if let dropdown = view?.slot("searchBarAccessory") {
                            DropdownView(node: dropdown, session: session).equatable()
                        }
                    }
                } content: {
                    content(view: view, actions: actions)
                }
            }
            if let alert = session.alert {
                ConfirmAlertOverlay(session: session, alert: alert)
            }
        }
    }

    /// What is under the header: the view's body, then the footer.
    @ViewBuilder
    private func content(view: Node?, actions: [Node]) -> some View {
        Group {
            if let view {
                switch view.type {
                case "List", "Grid": ListBody(session: session, view: view)
                case "Detail": DetailBody(node: view, assetsPath: session.command.assetsPath).equatable()
                case "Form": FormBody(session: session, focusToken: model.focusToken)
                default: Placeholder(title: String(localized: "\(view.type) isn't supported yet", bundle: .floe, comment: "The placeholder is the name of a kind of view, such as Grid."), detail: String(localized: "Floe renders List, Grid, Detail and Form.", bundle: .floe, comment: "List, Grid, Detail and Form are names from the extension API and stay as written."), systemImage: "hammer")
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if session.actionMenuOpen {
                ActionMenu(session: session)
            }
        }
        .thawAnimation(ThawMotion.quick, value: session.actionMenuOpen)
        Footer(
            primary: actions.first?.string("title"),
            primaryTakesCommand: view?.type == "Form",
            runPrimary: {
                if let first = session.actions.first {
                    session.run(first)
                }
            },
            showActions: actions.count > 1 ? { session.actionMenuOpen = true } : nil,
            leading: {
                if let toast = session.toast {
                    ToastView(session: session, toast: toast)
                } else {
                    IconView(value: session.command.icon ?? "icon:Terminal", assetsPath: session.command.assetsPath, size: 16)
                    Text(view?.string("navigationTitle") ?? session.command.title).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        )
    }
}

struct Placeholder: View {
    let title: String
    var detail: String?
    var systemImage = "magnifyingglass"
    var body: some View {
        ThawEmptyState(systemImage: systemImage, title: .verbatim(title), caption: detail.map { .verbatim($0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToastView: View {
    @ObservedObject var session: ExtensionSession
    let toast: ToastState
    var body: some View {
        HStack(spacing: 7) {
            if toast.style == "animated" {
                ProgressView().controlSize(.small)
            } else {
                Circle().fill(toast.style == "failure" ? Color.red : Color.green).frame(width: 8, height: 8)
            }
            Text(toast.title).fontWeight(.medium).lineLimit(1)
            if let message = toast.message {
                Text(message).foregroundStyle(.secondary).lineLimit(1)
            }
            if let primary = toast.primaryTitle {
                Button(primary) { session.runToastAction(primary: true) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                KeyCapView(text: "⌘")
                KeyCapView(systemImage: "return")
            }
            if let secondary = toast.secondaryTitle {
                Button(secondary) { session.runToastAction(primary: false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// An in-panel `confirmAlert` dialog.
struct ConfirmAlertOverlay: View {
    @ObservedObject var session: ExtensionSession
    let alert: AlertState

    var body: some View {
        PanelQuestionCard(
            title: alert.title,
            message: alert.message,
            primaryTitle: alert.primaryTitle,
            dismissTitle: alert.dismissTitle,
            isDestructive: alert.isDestructive,
            icon: alert.icon,
            assetsPath: session.command.assetsPath
        ) { session.resolveAlert($0) }
    }
}

/// A question in the panel: a scrim over the content with a centered card. The panel's keys answer it too.
struct PanelQuestionCard: View {
    let title: String
    let message: String?
    let primaryTitle: String
    let dismissTitle: String
    let isDestructive: Bool
    var icon: Any?
    var assetsPath = ""
    let answer: (Bool) -> Void
    @FocusState private var confirmFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
            VStack(alignment: .leading, spacing: ThawSpacing.row) {
                if let icon {
                    IconView(value: icon, assetsPath: assetsPath, size: 32)
                }
                Text(title)
                    .font(ThawType.heading)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(ThawType.body)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: ThawSpacing.base) {
                    Spacer(minLength: 0)
                    Button(dismissTitle) { answer(false) }
                        .keyboardShortcut(.cancelAction)
                    if isDestructive {
                        Button(primaryTitle) { answer(true) }
                            .foregroundStyle(.red)
                            .keyboardShortcut(.defaultAction)
                            .focused($confirmFocused)
                    } else {
                        Button(primaryTitle) { answer(true) }
                            .buttonStyle(.thawProminent)
                            .keyboardShortcut(.defaultAction)
                            .focused($confirmFocused)
                    }
                }
                .padding(.top, ThawSpacing.tight)
            }
            .padding(ThawSpacing.gutter)
            .frame(width: 340)
            .background(.background, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
            .onAppear { confirmFocused = true }
        }
    }
}

/// A list's dropdown. Its items are walked for the title only when the host sent the dropdown anew, not at every keystroke.
struct DropdownView: View, Equatable {
    let node: Node
    let session: ExtensionSession

    static func == (lhs: DropdownView, rhs: DropdownView) -> Bool {
        lhs.node.revision == rhs.node.revision && lhs.session === rhs.session
    }

    var body: some View {
        let entries = DropdownMenu.entries(for: node)
        let current = node.props["value"] as? String
        Button {
            DropdownMenu.open(entries, current: current) { session.event(node, "onChange", [$0]) }
        } label: {
            HStack(spacing: ThawSpacing.tight) {
                Text(DropdownMenu.title(of: current, in: entries) ?? node.string("placeholder") ?? String(localized: "Select", bundle: .floe, comment: "The label of a menu before anything is chosen in it."))
                Image(systemName: "chevron.up.chevron.down").font(ThawType.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .help(node.string("tooltip") ?? "")
    }
}

/// An extension's ⌘K, drawn by the action panel Floe's own rows use too.
struct ActionMenu: View {
    @ObservedObject var session: ExtensionSession

    var body: some View {
        ActionPanelCard(
            entries: session.panelEntries,
            query: session.panelQuery,
            submenuTitle: session.panelSubmenuTitle,
            selection: session.panelSelection
        ) { session.activateMenuEntry(at: $0) }
    }
}

/// The extension's ActionPanel, as the action panel lists and drives it.
extension ExtensionSession: ActionPanelDriver {
    var panelEntries: [ActionPanelEntry] {
        menuEntries.map { entry in
            let action = entry.node
            return ActionPanelEntry(
                id: entry.id,
                title: action.string("title") ?? String(localized: "Action", bundle: .floe, comment: "Stands in for an action's title when the extension gave none."),
                icon: .icon(action.props["icon"], assetsPath: command.assetsPath),
                section: entry.section,
                keys: Shortcuts.label(action.props["shortcut"]).map(ActionPanelEntry.Keys.label),
                isSubmenu: entry.isSubmenu,
                isDestructive: action.props["style"] as? String == "destructive"
            )
        }
    }

    var panelQuery: String {
        get { actionQuery }
        set { actionQuery = newValue }
    }

    var panelSelection: Int {
        get { actionSelection }
        set { actionSelection = newValue }
    }

    var panelSubmenuTitle: String? {
        actionPath.last.map { $0.string("title") ?? String(localized: "Submenu", bundle: .floe, comment: "Stands in for a submenu's title when the extension gave none.") }
    }

    func activatePanelEntry(at index: Int) {
        activateMenuEntry(at: index)
    }

    func openPanelSubmenu(at index: Int) {
        let entries = menuEntries
        if entries.indices.contains(index), entries[index].isSubmenu {
            openSubmenu(entries[index].node)
        }
    }

    func stepBackInPanel() {
        closeSubmenuOrMenu()
    }

    func closePanel() {
        actionMenuOpen = false
    }
}
