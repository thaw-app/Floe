//
//  MainMenu.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

enum MainMenu {
    /// Floe has no menu bar of its own unless it is in the Dock, but the main menu is still where
    /// AppKit looks up key equivalents: without it ⌘Q, ⌘W and the editing keys do nothing.
    /// Window-owning processes keep the full menu. The resident omits the entire Window submenu:
    /// AX queries would otherwise populate AppKit's window commands and retain several MiB.
    static func make(target: AnyObject, about: Selector, settings: Selector, includesWindowMenu: Bool = true) -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About Floe", bundle: .floe), action: about, keyEquivalent: "").target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Settings…", bundle: .floe), action: settings, keyEquivalent: ",").target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide Floe", bundle: .floe), action: #selector(NSApplication.hide), keyEquivalent: "h")
        appMenu.addItem(withTitle: String(localized: "Quit Floe", bundle: .floe), action: #selector(NSApplication.terminate), keyEquivalent: "q")

        // Sent to whatever has focus, which is how a text field gets Select All, Copy and Paste.
        let editMenu = NSMenu(title: String(localized: "Edit", bundle: .floe, comment: "The title of the Edit menu in the menu bar."))
        editMenu.addItem(withTitle: String(localized: "Undo", bundle: .floe), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Redo", bundle: .floe), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut", bundle: .floe), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy", bundle: .floe, comment: "A verb: put the selection on the clipboard."), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste", bundle: .floe, comment: "A verb: insert what is on the clipboard."), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All", bundle: .floe), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        var submenus = [appMenu, editMenu]
        if includesWindowMenu {
            let windowMenu = NSMenu(title: String(localized: "Window", bundle: .floe, comment: "The title of the Window menu in the menu bar."))
            windowMenu.addItem(withTitle: String(localized: "Close Window", bundle: .floe), action: #selector(NSWindow.performClose), keyEquivalent: "w")
            windowMenu.addItem(withTitle: String(localized: "Minimize", bundle: .floe), action: #selector(NSWindow.performMiniaturize), keyEquivalent: "m")
            NSApp.windowsMenu = windowMenu
            submenus.append(windowMenu)
        }

        let mainMenu = NSMenu()
        for submenu in submenus {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
