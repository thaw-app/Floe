//
//  CommandsSearchEntries.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchEntry {
    /// An entry on the Commands pane.
    static func commands(
        _ id: String,
        _ title: String,
        description: String? = nil,
        section: String? = nil,
        keywords: [String]
    ) -> SearchEntry {
        SearchEntry(
            id: "commands.\(id)",
            title: title,
            descriptionText: description,
            pane: .commands,
            section: section,
            keywords: keywords
        )
    }
}

extension SearchIndex {
    /// The Commands pane's controls, in the order the pane shows them.
    static let commandsEntries: [SearchEntry] = [
        .commands(
            "builtInHotkeys",
            String(localized: "Built-in Commands", bundle: .floe),
            section: String(localized: "Built-in Commands", bundle: .floe),
            keywords: String(
                localized: "hotkey, shortcut, keyboard, alias, emoji, clipboard, file search, system commands, lock, sleep, play, pause",
                bundle: .floe,
                comment: "Words that find the hotkeys and aliases of Floe's own commands in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "menuBarSearchHotkey",
            String(localized: "Search Menu Bar Items", bundle: .floe),
            description: String(localized: "Find an item in the menu bar and open its menu.", bundle: .floe),
            section: String(localized: "Built-in Commands", bundle: .floe),
            keywords: String(
                localized: "hotkey, shortcut, keyboard, alias, menu bar, status items, icons",
                bundle: .floe,
                comment: "Words that find the Search Menu Bar Items setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "emojiSkinTone",
            String(localized: "Emoji skin tone", bundle: .floe),
            section: String(localized: "Built-in Commands", bundle: .floe),
            keywords: String(
                localized: "emoji, skin tone, skin colour, skin color, hand, people",
                bundle: .floe,
                comment: "Words that find the Emoji skin tone setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "focusShortcut",
            String(localized: "Shortcut for Focus", bundle: .floe),
            description: String(localized: "A Shortcut of yours that sets Focus. It receives the number of minutes, or the word off or toggle.", bundle: .floe),
            section: String(localized: "Built-in Commands", bundle: .floe),
            keywords: String(
                localized: "focus, do not disturb, dnd, shortcut, shortcuts, notifications, quiet",
                bundle: .floe,
                comment: "Words that find the Shortcut for Focus setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "thawSupport",
            String(localized: "Thaw", bundle: .floe, comment: "Thaw is the name of an app."),
            description: String(localized: "Thaw's actions are in the search: type “thaw” to see them.", bundle: .floe, comment: "The word in quotation marks is typed as it is and stays in English."),
            section: String(localized: "Built-in Commands", bundle: .floe),
            keywords: String(
                localized: "thaw, hidden items, thaw bar, menu bar manager",
                bundle: .floe,
                comment: "Words that find the Thaw setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "runsShellCommands",
            String(localized: "Run shell commands from the search", bundle: .floe),
            section: String(localized: "Shell Commands", bundle: .floe),
            keywords: String(
                localized: "shell, command, terminal, command line, run, prefix, script, bash, zsh",
                bundle: .floe,
                comment: "Words that find the Run shell commands setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "suggestsShellCommands",
            String(localized: "Suggest while typing a command", bundle: .floe),
            section: String(localized: "Shell Commands", bundle: .floe),
            keywords: String(
                localized: "history, completion, autocomplete, tab, suggestions, zsh history, programs, paths",
                bundle: .floe,
                comment: "Words that find the Suggest while typing a command setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "recognizesCommands",
            String(localized: "Recognize commands without the prefix", bundle: .floe),
            section: String(localized: "Shell Commands", bundle: .floe),
            keywords: String(
                localized: "recognize, detect, prefix, command, automatic, without prefix",
                bundle: .floe,
                comment: "Words that find the Recognize commands without the prefix setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "includeRaycastExtensions",
            String(localized: "Include extensions installed in Raycast", bundle: .floe),
            description: String(localized: "Reads ~/.config/raycast/extensions. Their Raycast settings don't carry over.", bundle: .floe),
            section: String(localized: "Extensions", bundle: .floe, comment: "The heading over the settings for extensions."),
            keywords: String(
                localized: "raycast, import, store, installed",
                bundle: .floe,
                comment: "Words that find the Include extensions installed in Raycast setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "extensionsFolder",
            String(localized: "Extensions folder", bundle: .floe),
            section: String(localized: "Extensions", bundle: .floe, comment: "The heading over the settings for extensions."),
            keywords: String(
                localized: "finder, directory, location, path, install, show in finder",
                bundle: .floe,
                comment: "Words that find the Extensions folder setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "runtime",
            String(localized: "Runtime", bundle: .floe, comment: "The program that runs extensions."),
            section: String(localized: "Extensions", bundle: .floe, comment: "The heading over the settings for extensions."),
            keywords: String(
                localized: "bun, javascript, node, engine",
                bundle: .floe,
                comment: "Words that find the Runtime setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "scriptsFolder",
            String(localized: "Scripts folder", bundle: .floe),
            section: String(localized: "Script Commands", bundle: .floe),
            keywords: String(
                localized: "script, scripts, script commands, raycast, finder, directory, new script",
                bundle: .floe,
                comment: "Words that find the Scripts folder setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .commands(
            "menuBarCommands",
            String(localized: "Extension Commands in the Menu Bar", bundle: .floe),
            description: String(localized: "Which extension commands have an item in the menu bar.", bundle: .floe),
            section: String(localized: "Menu Bar Commands", bundle: .floe),
            keywords: String(
                localized: "status item, extension, show, remove",
                bundle: .floe,
                comment: "Words that find the Extension Commands in the Menu Bar setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]
}
