//
//  Session+ViewState.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What a session's view shows, derived from the last render (see ViewState.swift).
extension ExtensionSession {
    var screen: Node? {
        ViewState.screen(in: root)
    }

    var view: Node? {
        ViewState.view(in: root)
    }

    var isList: Bool {
        ViewState.isList(view)
    }

    var selectedRow: Row? {
        ViewState.selectedRow(rows, selection: selection)
    }

    var actionPanel: Node? {
        ViewState.actionPanel(view: view, selectedRow: selectedRow)
    }

    var actions: [Node] {
        ViewState.actions(in: actionPanel)
    }

    /// How a Grid lays out the rows on show; nil when the view is no Grid.
    var gridLayout: GridLayout? {
        guard let view, view.type == "Grid" else { return nil }
        return GridLayout(view: view, rows: rows)
    }

    /// ← and → in a Grid step to the item before or after; false when the view is no Grid or the menu is open.
    func stepInGrid(by delta: Int) -> Bool {
        guard !actionMenuOpen, let grid = gridLayout else { return false }
        selection = grid.moved(from: min(selection, rows.count - 1), across: delta)
        return true
    }

    var menuEntries: [MenuEntry] {
        ViewState.menuEntries(in: actionPath.last ?? actionPanel, query: actionQuery)
    }

    /// Tells the extension which item is selected, by its `id` prop, whenever that changes.
    func reportSelection() {
        guard let view, view.handlers.contains("onSelectionChange") else { return }
        let id = selectedRow?.node.string("id")
        guard id != reportedItemID else { return }
        reportedItemID = id
        event(view, "onSelectionChange", [id.map { $0 as Any } ?? NSNull()])
    }

    /// Moves to the item `selectedItemId` names, once it is there and each time it names another.
    func followSelectedItem() {
        guard let wanted = view?.string("selectedItemId"), wanted != followedItemID,
              let index = rows.firstIndex(where: { $0.node.string("id") == wanted })
        else { return }
        followedItemID = wanted
        selection = index
    }

    /// The last rows came on screen: asks for the next page, once per page, while there is one and none is loading.
    func loadMore() {
        guard let view, view.handlers.contains("onLoadMore"), view.bool("hasMore"), !view.bool("isLoading"), loadMoreAsked != rows.count else { return }
        loadMoreAsked = rows.count
        event(view, "onLoadMore")
    }
}
