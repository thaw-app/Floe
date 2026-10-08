//
//  SearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What a provider may know about one root search. The model builds it; providers read nothing else from the model.
struct SearchContext {
    /// The query as typed. Ranking and the calculator read it untrimmed.
    let query: String
    let trimmed: String
    var favorites: [String] = []
    /// Results the user took out of the search, by `RootItem.id`.
    var hidden: Set<String> = []
    var emojiSkinTone = EmojiSkinTone.none
    /// How shell commands are treated. A context made by hand has them off, so a test of another provider sees none.
    var shell = ShellSettings.off
    var checkpoints: [Checkpoint] = []
    /// The names of the user's lists in Reminders. Filled only while a reminder is being typed.
    var reminderLists: [String] = []
    var aliases: [String: String] = [:]
    var notesApp = NotesApp.appleNotes
    var frecency: (String) -> Double = { _ in 0 }
    var commands: [ExtensionCommand] = []
    var scripts: [ScriptCommand] = []
    var apps: [AppEntry] = []
    /// What Thaw can be asked to do; empty when Thaw is not installed.
    var thawActions: [ThawAction] = []
    /// The terminal and the editor as they resolve now; empty when neither has an app.
    var preferredApps: [RoleApp] = []
    /// Where the Clipboard History command goes: Floe's own history, or the app chosen for the role.
    var clipboardDestination = ClipboardDestination.floe
    var settingsPanes: [SystemSettingsPane] = []
    /// The hosts of the SSH configuration; empty when there is none.
    var sshHosts: [SSHHost] = []
    /// The user's shortcuts from the Shortcuts app; empty while their switch in Privacy is off.
    var shortcuts: [AppleShortcut] = []
    var snippets: [Snippet] = []
    var quicklinks: [Quicklink] = []
    /// The names the user gave menu bar items, by item id.
    var menuBarItemNames: [String: String] = [:]
    /// Whether an AI source can answer; the Ask AI rows are left out when none can.
    var canAskAI = false

    init(query: String) {
        self.query = query
        trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SearchContext {
    /// The text a query hands to a keyword: the keyword in any case, a space, then some text. The keyword
    /// alone is an ordinary search, and a quicklink or a script that answers to the same word keeps it.
    func text(after keyword: String) -> String? {
        guard trimmed.lowercased().hasPrefix(keyword.lowercased() + " ") else { return nil }
        let text = trimmed.dropFirst(keyword.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              QuicklinkSearchProvider.keywordSearchResult(query: trimmed, links: quicklinks) == nil,
              !scripts.contains(where: { $0.argumentsText(in: trimmed) != nil })
        else { return nil }
        return text
    }
}

/// What one provider adds to the root search for one query.
struct SearchContribution {
    /// Ranked with every other provider's: browsed without a query, scored against it with one.
    var ranked: [RootItem] = []
    /// Ranked only once there is a query; without one they show only as a favorite or a suggestion.
    var searchOnly: [RootItem] = []
    /// Above the ranked rows, in place of a ranked row with the same id.
    var pinned: [RootResult] = []
    /// Above everything else, under their own section titles.
    var sectioned: [RootResult] = []
    /// Below the ranked rows.
    var appended: [RootResult] = []
}

protocol SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution
}
