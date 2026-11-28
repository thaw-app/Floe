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
        let search = MenuItemSearchModel(environment: menuItemEnvironment)
        search.host = modeHost { [weak self] in self?.closeMenuItemSearch() }
        enter(.menuItemSearch(search))
        panelHost.showPanel()
        focusToken += 1
        search.scan()
    }

    /// Accessibility was just granted, in the welcome window or in System Settings: the searches that read
    /// other apps read them now.
    func accessibilityWasGranted() {
        menuBarSearch.accessWasGranted()
        // Also a search under another mode, so it shows the menus when it is back on screen.
        for case let .menuItemSearch(search) in modes.modes {
            search.scan()
        }
        refresh()
    }

    func closeMenuItemSearch() {
        leave(.menuItemSearch)
        focusToken += 1
    }
}
