//
//  Model+Hotkeys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Floe's own commands that a hotkey can run from anywhere: its views and the system commands.
extension LauncherModel {
    /// The views, in the order Settings lists them.
    static let hotkeyViews: [RootItem] = [.menuBarSearch, .emojiSearch, .clipboardHistory, .fileSearch]

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
        case .emojiSearch:
            reset()
            query = EmojiSearchProvider.prefix
            showPanel()
            focusToken += 1
        case .clipboardHistory:
            openClipboardHistory()
        case .fileSearch:
            reset()
            openFileSearch(with: "")
        case let .system(command):
            runSystemCommand(command)
        default:
            break
        }
    }
}
