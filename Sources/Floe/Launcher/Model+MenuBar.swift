//
//  Model+MenuBar.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Showing and leaving the menu bar item search; the search itself is `MenuBarSearchModel`.
extension LauncherModel {
    /// Switches the panel to the menu bar item search and rescans the menu bar.
    func openMenuBarSearch() {
        if let presentInPanelProcess = panelHost.presentInPanelProcess, let key = RootItem.menuBarSearch.settingsKey {
            presentInPanelProcess(.builtIn(key))
            return
        }
        runner.endOpenCommand()
        setup = nil
        isShowingClipboardHistory = false
        closeNoteDesk()
        isSearchingMenuBar = true
        if !settings.rememberMenuBarQuery {
            menuBarSearch.query = ""
        }
        panelHost.showPanel()
        focusToken += 1
        menuBarSearch.scan()
    }

    func closeMenuBarSearch() {
        isSearchingMenuBar = false
        focusToken += 1
    }
}
