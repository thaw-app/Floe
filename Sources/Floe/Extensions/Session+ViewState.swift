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

    var menuEntries: [MenuEntry] {
        ViewState.menuEntries(in: actionPath.last ?? actionPanel, query: actionQuery)
    }
}
