//
//  AppleShortcutSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchSourceInfo {
    /// Not a source with a section of its own: its rows are ranked with everything else. It is
    /// listed with the sources because it too reads from another app only once it is switched on.
    static let shortcuts = SearchSourceInfo(
        id: "shortcuts",
        title: String(localized: "Apple Shortcuts", bundle: .floe),
        detail: String(localized: "Finds the shortcuts you made in the Shortcuts app by name and runs the one you pick. Floe asks the Shortcuts command line tool for the names each time the launcher opens. The list stays on this Mac and is not saved. Type “shortcuts” and a space to see them all.", bundle: .floe, comment: "“shortcuts” is a word the user types. It is a command and stays in English.")
    )

    /// Every switch under Search Sources on the Privacy page.
    static let switches = all + [shortcuts]
}

extension SearchContext {
    var shortcutRows: [RootItem] {
        shortcuts.map(RootItem.shortcut)
    }
}

/// The user's shortcuts. Like System Settings' panes they are only searched for.
struct AppleShortcutSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        SearchContribution(searchOnly: context.shortcutRows)
    }
}

/// `shortcuts mail`: the shortcuts that match, and every shortcut for the keyword and a space alone.
struct AppleShortcutSearchScope: SearchScope {
    nonisolated static let word = "shortcuts"

    let keyword = Self.word
    let title = String(localized: "Shortcuts", bundle: .floe, comment: "A section title. Shortcuts are what the user makes in Apple's Shortcuts app.")
    let emptyTitle = String(localized: "No shortcuts match", bundle: .floe)

    /// With the switch off or no shortcuts the word is not a scope, so a search that starts with it stays an ordinary one.
    func text(in context: SearchContext) -> String? {
        guard !context.shortcuts.isEmpty else { return nil }
        return context.text(afterOrWithSpace: keyword)
    }

    func results(for text: String, context: SearchContext) -> [RootItem] {
        context.ranked(context.shortcutRows, for: text)
    }
}
