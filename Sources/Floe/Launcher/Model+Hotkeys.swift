//
//  Model+Hotkeys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ThawUI

/// Floe's own commands that a hotkey can run from anywhere: its views and the system commands.
extension LauncherModel {
    /// The views, in the order Settings lists them.
    static let hotkeyViews: [RootItem] = [.menuBarSearch, .menuItemSearch, .emojiSearch, .clipboardHistory, .fileSearch, .noteDesk, .floatingNote]

    static var hotkeyItems: [RootItem] {
        hotkeyViews + SystemCommand.allCases.map(RootItem.system)
    }

    /// Each built-in command that has a hotkey, with the keys that run it.
    static func assigned(_ hotkeys: [String: KeyCombination]) -> [(item: RootItem, keys: KeyCombination)] {
        hotkeyItems.compactMap { item in item.settingsKey.flatMap { hotkeys[$0] }.map { (item, $0) } }
    }

    /// A view opens the panel on itself, whatever the panel was showing. A system command runs with the panel closed.
    func runFromHotkey(_ item: RootItem) {
        switch item {
        case .menuBarSearch:
            openMenuBarSearch()
        case .menuItemSearch:
            openMenuItemSearch()
        case .emojiSearch:
            reset()
            query = EmojiSearchProvider.prefix
            panelHost.showPanel()
            focusToken += 1
        case .clipboardHistory:
            openClipboardHistory()
        case .fileSearch:
            reset()
            openFileSearch(with: "")
        case .noteDesk:
            reset()
            openNoteDesk()
        case .floatingNote:
            openFloatingNote()
        case let .system(command):
            features.system.run(command)
        default:
            break
        }
    }

    /// An app's hotkey runs what Return on apps does, when the user chose it and it is on offer. Otherwise it opens
    /// the app, or hides it if it's already in front, like a per-app hotkey in Thaw.
    func runAppHotkey(_ app: AppEntry) {
        usage.recordUse(of: RootItem.app(app).id)
        isRunningAppHotkey = true
        defer { isRunningAppHotkey = false }
        if features.actions.runFromHotkey(.app(app)) {
            return
        }
        if let running = NSWorkspace.shared.frontmostApplication, running.bundleURL?.standardizedFileURL == app.url.standardizedFileURL {
            running.hide()
        } else {
            NSWorkspace.shared.openWithoutWaiting(app.url)
        }
    }
}
