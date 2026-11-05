//
//  StatusMenu.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

enum StatusMenu {
    /// Floe's icon in the menu bar and its menu, with the Show Floe item, which names the hotkey once it is known.
    static func make(target: AnyObject, show: Selector, about: Selector, settings: Selector) -> (item: NSStatusItem, showItem: NSMenuItem) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarGlyph.image()
        let menu = NSMenu()
        let showItem = menu.addItem(withTitle: String(localized: "Show Floe", bundle: .floe), action: show, keyEquivalent: "")
        showItem.target = target
        menu.addItem(withTitle: String(localized: "About Floe", bundle: .floe), action: about, keyEquivalent: "").target = target
        // Nil until Info.plist carries a Sparkle public key.
        if let updateItem = UpdatesManager.shared.makeMenuItem() {
            menu.addItem(updateItem)
        }
        menu.addItem(withTitle: String(localized: "Settings…", bundle: .floe), action: settings, keyEquivalent: ",").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit", bundle: .floe, comment: "The menu item that quits Floe."), action: #selector(NSApplication.terminate), keyEquivalent: "q")
        item.menu = menu
        return (item, showItem)
    }
}
