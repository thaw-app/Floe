//
//  ItemActionPanel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Floe's own Actions menu, open in the panel: the rows of the selected result, of the main search, File Search,
/// menu bar search or Ask AI, with their keys and submenus, as an extension's ⌘K shows its own.
final class ItemActionPanel: ObservableObject, ActionPanelDriver {
    /// The rows as the view built them; nil is a separator.
    let rows: [ItemAction?]
    /// Open submenus, outermost first.
    @Published private(set) var path: [ItemAction] = []
    @Published var panelQuery = "" {
        didSet { panelSelection = 0 }
    }

    @Published var panelSelection = 0
    private let close: () -> Void

    init(rows: [ItemAction?], close: @escaping () -> Void) {
        self.rows = rows
        self.close = close
    }

    /// The rows on screen with whether a separator comes before each: the open submenu's, or the top's. A search
    /// lists every row under the open submenu, or the top, whose title has it, as an extension's does: rows that
    /// run something, those in submenus included, with no separators.
    var shown: [(action: ItemAction, startsGroup: Bool)] {
        guard panelQuery.isEmpty else {
            return Self.flattened(path.last?.children ?? rows.compactMap(\.self))
                .filter { $0.children.isEmpty && $0.title.localizedStandardContains(panelQuery) }
                .map { ($0, false) }
        }
        let level = path.last.map { $0.children.map(Optional.some) } ?? rows
        var shown: [(action: ItemAction, startsGroup: Bool)] = []
        var parted = false
        for row in level {
            guard let row else {
                parted = true
                continue
            }
            shown.append((row, parted && !shown.isEmpty))
            parted = false
        }
        return shown
    }

    var panelEntries: [ActionPanelEntry] {
        shown.enumerated().map { index, row in
            ActionPanelEntry(
                id: index,
                title: row.action.title,
                icon: row.action.icon.map { .custom(AnyView(Image(nsImage: $0).resizable().scaledToFit().frame(width: ListStyle.imageSize, height: ListStyle.imageSize))) }
                    ?? .symbol(row.action.symbol),
                startsGroup: row.startsGroup,
                keys: row.action.shortcut.map(ActionPanelEntry.Keys.combination),
                isSubmenu: !row.action.children.isEmpty
            )
        }
    }

    var panelSubmenuTitle: String? {
        path.last?.title
    }

    func activatePanelEntry(at index: Int) {
        let shown = shown
        guard shown.indices.contains(index) else { return }
        let action = shown[index].action
        if !action.children.isEmpty {
            open(action)
            return
        }
        // Closed first, so a row that hides the panel or opens another view finds it gone.
        closePanel()
        action.run()
    }

    func openPanelSubmenu(at index: Int) {
        let shown = shown
        guard shown.indices.contains(index), !shown[index].action.children.isEmpty else { return }
        open(shown[index].action)
    }

    func stepBackInPanel() {
        if !panelQuery.isEmpty {
            panelQuery = ""
        } else if path.isEmpty {
            closePanel()
        } else {
            path.removeLast()
            panelSelection = 0
        }
    }

    func closePanel() {
        close()
    }

    /// A row's keys, pressed with the panel open, run that row of the rows the panel shows, as a menu's keys run its
    /// own items: the result they were built for, whatever is selected under the panel by now. False when no row has
    /// them, a submenu's rows included.
    func runRow(withKeys pressed: KeyCombination) -> Bool {
        guard let row = Self.flattened(rows.compactMap(\.self)).first(where: { $0.children.isEmpty && $0.shortcut == pressed }) else {
            return false
        }
        closePanel()
        row.run()
        return true
    }

    private func open(_ submenu: ItemAction) {
        path.append(submenu)
        panelQuery = ""
        panelSelection = 0
    }

    /// Every row, each submenu's rows right after it.
    private static func flattened(_ actions: [ItemAction]) -> [ItemAction] {
        actions.flatMap { [$0] + flattened($0.children) }
    }
}

/// Whether Floe's own Actions menu is open, and on which rows. Kept apart from the launcher model, so opening and
/// closing it draws only the panel.
final class ActionPanelPresenter: ObservableObject {
    @Published private(set) var panel: ItemActionPanel?

    /// ⌘K and the Actions button: opens the panel on the rows, or closes it when it is open. With no rows there
    /// is nothing to open.
    func toggle(_ rows: [ItemAction?]) {
        if panel != nil {
            panel = nil
        } else if rows.contains(where: { $0 != nil }) {
            panel = ItemActionPanel(rows: rows) { [weak self] in self?.panel = nil }
        }
    }

    func close() {
        if panel != nil {
            panel = nil
        }
    }
}

/// Draws Floe's own Actions menu over a view's rows, above its bottom bar. A click beside it closes it, as a click
/// outside a menu does, and so does the view going: the rows are that view's, and another view, or a command or a
/// list a hotkey opened, would draw or take its keys over them.
struct ActionPanelOverlay: ViewModifier {
    @ObservedObject var presenter: ActionPanelPresenter

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if let panel = presenter.panel {
                    GeometryReader { space in
                        ZStack(alignment: .bottomTrailing) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { presenter.close() }
                            ItemActionPanelCard(panel: panel, room: space.size.height)
                        }
                    }
                }
            }
            .thawAnimation(ThawMotion.quick, value: presenter.panel != nil)
            .onDisappear { presenter.close() }
    }
}

extension View {
    /// Floe's own Actions menu, drawn over this view when it opens.
    func actionPanel(_ presenter: ActionPanelPresenter) -> some View {
        modifier(ActionPanelOverlay(presenter: presenter))
    }
}

private struct ItemActionPanelCard: View {
    @ObservedObject var panel: ItemActionPanel
    let room: CGFloat

    var body: some View {
        ActionPanelCard(
            entries: panel.panelEntries,
            query: panel.panelQuery,
            submenuTitle: panel.panelSubmenuTitle,
            selection: panel.panelSelection,
            room: room
        ) { panel.activatePanelEntry(at: $0) }
    }
}
