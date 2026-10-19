//
//  MenuItemRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Search Menu Items, and the menu commands of the front app that `menus` found: Return chooses one.
final class MenuItemRows {
    var host = RowHost()
    /// Shows the search of the front app's menus in the panel.
    var openSearch: () -> Void = { /* set by LauncherFeatures */ }
    /// Stands in for pressing the item. Tests replace it: the real thing reaches into another app.
    var choose: (AppMenuItem, MenuTarget) -> Void = { MenuItems.choose($0, in: $1) }

    static let chooseTitle = String(localized: "Choose Command", bundle: .floe, comment: "A button that runs the selected command of an app's menus.")

    static func title(for row: MenuItemRow) -> String {
        switch row {
        case .item: chooseTitle
        case .access: String(localized: "Open Privacy Settings", bundle: .floe, comment: "A button that opens the Privacy pane of System Settings.")
        }
    }

    /// Return on a command: the launcher goes first, so the command acts on the app and not on the launcher.
    func open(_ row: MenuItemRow) {
        switch row {
        case let .item(entry, target):
            host.leave()
            choose(entry, target)
        case .access:
            AppPermissions.shared.accessibility.performRequest()
        }
    }
}

extension MenuItemRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case let .menuItem(row) = item else { return nil }
        return Self.title(for: row)
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case .menuItemSearch: openSearch()
        case let .menuItem(row): open(row)
        default: return false
        }
        return true
    }
}
