//
//  Model+MenuItems.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Showing and leaving the search of the front app's menus; the search itself is `MenuItemSearchModel`.
extension LauncherModel {
    /// Switches the panel to the menus of the app in front, read afresh each time.
    func openMenuItemSearch() {
        runner.endOpenCommand()
        setup = nil
        isSearchingMenuBar = false
        isShowingClipboardHistory = false
        isSearchingFiles = false
        closeNoteDesk()
        let search = MenuItemSearchModel(environment: menuItemEnvironment)
        search.host = modeHost { [weak self] in self?.closeMenuItemSearch() }
        menuItemSearch = search
        panelHost.showPanel()
        focusToken += 1
        search.scan()
    }

    /// Accessibility was just granted, in the welcome window or in System Settings: the searches that read
    /// other apps read them now.
    func accessibilityWasGranted() {
        menuBarSearch.accessWasGranted()
        menuItemSearch?.scan()
        refresh()
    }

    func closeMenuItemSearch() {
        menuItemSearch = nil
        focusToken += 1
    }
}
