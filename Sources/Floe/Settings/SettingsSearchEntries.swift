//
//  SettingsSearchEntries.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchPaneLabel {
    static let general = SearchPaneLabel(title: String(localized: "General", bundle: .floe, comment: "The name of a settings page."), symbol: "gearshape")
    static let applications = SearchPaneLabel(title: String(localized: "Applications", bundle: .floe, comment: "The name of a settings page."), symbol: "square.grid.2x2")
    static let quicklinks = SearchPaneLabel(title: String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."), symbol: "link")
    static let snippets = SearchPaneLabel(title: String(localized: "Snippets", bundle: .floe, comment: "The name of a settings page."), symbol: "text.quote")
    static let extensionStore = SearchPaneLabel(title: String(localized: "Extension Store", bundle: .floe, comment: "The name of a settings page."), symbol: "bag")
    static let appearance = SearchPaneLabel(title: String(localized: "Appearance", bundle: .floe, comment: "The name of a settings page."), symbol: "paintbrush")
    static let privacy = SearchPaneLabel(title: String(localized: "Privacy", bundle: .floe, comment: "The name of a settings page."), symbol: "hand.raised")
    static let about = SearchPaneLabel(title: String(localized: "About", bundle: .floe, comment: "The name of a settings page."), symbol: "cube")
}

extension SearchPane {
    static let general = SearchPane(page: .general, label: .general)
    static let applications = SearchPane(page: .applications, label: .applications)
    static let quicklinks = SearchPane(page: .quicklinks, label: .quicklinks)
    static let snippets = SearchPane(page: .snippets, label: .snippets)
    static let extensionStore = SearchPane(page: .extensionStore, label: .extensionStore)
    static let appearance = SearchPane(page: .appearance, label: .appearance)
    static let privacy = SearchPane(page: .privacy, label: .privacy)
    static let about = SearchPane(page: .about, label: .about)
}

extension String {
    /// The search terms in one translated list. A translator writes as many as the language needs, with commas between them.
    nonisolated var searchTerms: [String] {
        split { ",，、،".contains($0) }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension SearchEntry {
    /// An entry on the Appearance pane.
    static func appearance(
        _ id: String,
        _ title: String,
        description: String? = nil,
        section: String? = nil,
        keywords: [String]
    ) -> SearchEntry {
        SearchEntry(
            id: "appearance.\(id)",
            title: title,
            descriptionText: description,
            pane: .appearance,
            section: section,
            keywords: keywords
        )
    }

    /// An entry on the Quicklinks pane.
    static func quicklinks(
        _ id: String,
        _ title: String,
        description: String? = nil,
        section: String? = nil,
        keywords: [String]
    ) -> SearchEntry {
        SearchEntry(
            id: "quicklinks.\(id)",
            title: title,
            descriptionText: description,
            pane: .quicklinks,
            section: section,
            keywords: keywords
        )
    }

    /// An entry on the General pane.
    static func general(
        _ id: String,
        _ title: String,
        description: String? = nil,
        section: String? = nil,
        keywords: [String]
    ) -> SearchEntry {
        SearchEntry(
            id: "general.\(id)",
            title: title,
            descriptionText: description,
            pane: .general,
            section: section,
            keywords: keywords
        )
    }
}

/// What the settings search can find: one entry per control in the settings window.
///
/// Titles, sections and descriptions repeat what the panes in SettingsView.swift show, in the user's
/// language, which is also the language they are matched in. Ids are never translated. A pane
/// that gains a control adds an entry to its list here; a new pane adds a list and appends it
/// to SearchIndex.staticEntries.
extension SearchIndex {
    /// The panes themselves, so typing a pane's name finds it. Applications and About have no
    /// entries beyond these: one is a list of apps with its own filter, the other has no settings.
    static let paneEntries: [SearchEntry] = [
        SearchEntry(
            id: "pane.appearance",
            title: String(localized: "Appearance", bundle: .floe, comment: "The name of a settings page."),
            descriptionText: String(localized: "Tint, border and shadow for the launcher panel.", bundle: .floe),
            pane: .appearance,
            keywords: String(
                localized: "appearance, glass, tint, colour, color, gradient, border, shadow, theme, style",
                bundle: .floe,
                comment: "Words that find the Appearance page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "pane.privacy",
            title: String(localized: "Privacy", bundle: .floe, comment: "The name of a settings page."),
            descriptionText: String(localized: "Permissions and what Floe contacts.", bundle: .floe),
            pane: .privacy,
            keywords: String(
                localized: "privacy, permissions, network, analytics, tracking, data",
                bundle: .floe,
                comment: "Words that find the Privacy page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "pane.general",
            title: String(localized: "General", bundle: .floe, comment: "The name of a settings page."),
            pane: .general,
            keywords: String(
                localized: "settings, preferences, options",
                bundle: .floe,
                comment: "Words that find the General page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "pane.applications",
            title: String(localized: "Applications", bundle: .floe, comment: "The name of a settings page."),
            descriptionText: String(localized: "Aliases and hotkeys for apps.", bundle: .floe),
            pane: .applications,
            keywords: String(
                localized: "apps, alias, hotkey, shortcut, keyboard, filter",
                bundle: .floe,
                comment: "Words that find the Applications page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "pane.quicklinks",
            title: String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            descriptionText: String(localized: "Keywords and fallbacks for web search.", bundle: .floe),
            pane: .quicklinks,
            keywords: String(
                localized: "quicklink, quicklinks, keyword, search, web, fallback, link, url",
                bundle: .floe,
                comment: "Words that find the Quicklinks page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "pane.snippets",
            title: String(localized: "Snippets", bundle: .floe, comment: "The name of a settings page."),
            descriptionText: String(localized: "Text you paste or type by keyword.", bundle: .floe),
            pane: .snippets,
            keywords: String(
                localized: "snippet, snippets, text, expansion, expand, keyword, abbreviation, template",
                bundle: .floe,
                comment: "Words that find the Snippets page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "pane.extensionStore",
            title: String(localized: "Extension Store", bundle: .floe, comment: "The name of a settings page."),
            descriptionText: String(localized: "Install, update and remove extensions from the Raycast store.", bundle: .floe),
            pane: .extensionStore,
            keywords: String(
                localized: "store, install, update, remove, download, extensions, browse, raycast",
                bundle: .floe,
                comment: "Words that find the Extension Store page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "pane.about",
            title: String(localized: "About", bundle: .floe, comment: "The name of a settings page."),
            pane: .about,
            keywords: String(
                localized: "version, build, commit, update, what's new, release notes, changelog, license, credits, acknowledgements, source code, github, discord, report a bug, data folder",
                bundle: .floe,
                comment: "Words that find the About page in the settings search, separated by commas."
            ).searchTerms
        ),
    ]

    static let appearanceEntries: [SearchEntry] = [
        .appearance(
            "followThaw",
            String(localized: "Follow Thaw's Appearance", bundle: .floe),
            section: String(localized: "Thaw", bundle: .floe, comment: "Thaw is the name of an app."),
            keywords: String(
                localized: "thaw, follow, match, mirror, sync, same look",
                bundle: .floe,
                comment: "Words that find the Follow Thaw's Appearance setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "launcherLayout",
            String(localized: "Launcher layout", bundle: .floe),
            section: String(localized: "Layout", bundle: .floe, comment: "The heading over the settings for how the launcher is arranged."),
            keywords: String(
                localized: "layout, compact, extended, size, search bar, list",
                bundle: .floe,
                comment: "Words that find the Launcher layout setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "searchFieldShape",
            String(localized: "Search field shape", bundle: .floe),
            section: String(localized: "Layout", bundle: .floe, comment: "The heading over the settings for how the launcher is arranged."),
            keywords: String(
                localized: "shape, rounded, capsule, pill, square, corners, search bar, input",
                bundle: .floe,
                comment: "Words that find the Search field shape setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "separatesSearchField",
            String(localized: "Separate the search field from the results", bundle: .floe),
            section: String(localized: "Layout", bundle: .floe, comment: "The heading over the settings for how the launcher is arranged."),
            keywords: String(
                localized: "separate, split, detached, floating, two pieces, gap, search bar, input, results",
                bundle: .floe,
                comment: "Words that find the Separate the search field from the results setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "glassEffect",
            String(localized: "Glass Effect", bundle: .floe),
            section: String(localized: "Glass", bundle: .floe, comment: "The heading over the settings for the launcher's glass material."),
            keywords: String(
                localized: "glass, liquid, dynamic, clear, regular, effect, material",
                bundle: .floe,
                comment: "Words that find the Glass Effect setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "tintStyle",
            String(localized: "Tint", bundle: .floe, comment: "The colour laid over the launcher's glass."),
            section: String(localized: "Tint", bundle: .floe, comment: "The colour laid over the launcher's glass."),
            keywords: String(
                localized: "tint, colour, color, style, solid, gradient, none",
                bundle: .floe,
                comment: "Words that find the Tint setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "tintColor",
            String(localized: "Tint color", bundle: .floe),
            section: String(localized: "Tint", bundle: .floe, comment: "The colour laid over the launcher's glass."),
            keywords: String(
                localized: "tint, colour, color, picker",
                bundle: .floe,
                comment: "Words that find the Tint color setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "tintOpacity",
            String(localized: "Tint Opacity", bundle: .floe),
            section: String(localized: "Tint", bundle: .floe, comment: "The colour laid over the launcher's glass."),
            keywords: String(
                localized: "tint, opacity, strength, transparency",
                bundle: .floe,
                comment: "Words that find the Tint Opacity setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "border",
            String(localized: "Border", bundle: .floe, comment: "The line drawn around the launcher panel."),
            section: String(localized: "Border", bundle: .floe, comment: "The line drawn around the launcher panel."),
            keywords: String(
                localized: "border, outline, stroke, edge, width",
                bundle: .floe,
                comment: "Words that find the Border setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .appearance(
            "shadow",
            String(localized: "Drop shadow", bundle: .floe),
            section: String(localized: "Shadow", bundle: .floe, comment: "The heading over the launcher's shadow setting."),
            keywords: String(
                localized: "shadow, depth, drop",
                bundle: .floe,
                comment: "Words that find the Drop shadow setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]

    static let privacyEntries: [SearchEntry] = [
        privacy(
            "permissions",
            String(localized: "Permissions", bundle: .floe, comment: "What the app is allowed to do on this Mac."),
            section: String(localized: "Permissions", bundle: .floe, comment: "What the app is allowed to do on this Mac."),
            keywords: String(
                localized: "privacy, security, access, grant, allow, accessibility",
                bundle: .floe,
                comment: "Words that find the Permissions setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "accessibility",
            String(localized: "Accessibility", bundle: .floe, comment: "The macOS permission named Accessibility."),
            section: String(localized: "Permissions", bundle: .floe, comment: "What the app is allowed to do on this Mac."),
            keywords: String(
                localized: "permission, privacy, access, grant, trusted, menu bar",
                bundle: .floe,
                comment: "Words that find the Accessibility setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "network",
            String(localized: "Network Access", bundle: .floe),
            section: String(localized: "Network Access", bundle: .floe),
            keywords: String(
                localized: "network, internet, updates, github, ai, requests, analytics",
                bundle: .floe,
                comment: "Words that find the Network Access setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "searchSources",
            String(localized: "Search Sources", bundle: .floe),
            section: String(localized: "Search Sources", bundle: .floe),
            keywords: String(
                localized: "sources, root search, results, sections",
                bundle: .floe,
                comment: "Words that find the Search Sources setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "searchSources.files",
            String(localized: "Files", bundle: .floe, comment: "Files on this Mac, as a source of search results."),
            section: String(localized: "Search Sources", bundle: .floe),
            keywords: String(
                localized: "file search, spotlight, documents, source",
                bundle: .floe,
                comment: "Words that find the Files setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "searchSources.tabs",
            String(localized: "Browser Tabs", bundle: .floe),
            section: String(localized: "Search Sources", bundle: .floe),
            keywords: String(
                localized: "tabs, browser, safari, open tabs, automation, applescript, source",
                bundle: .floe,
                comment: "Words that find the Browser Tabs setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "searchSources.shortcuts",
            String(localized: "Apple Shortcuts", bundle: .floe),
            section: String(localized: "Search Sources", bundle: .floe),
            keywords: String(
                localized: "shortcuts, shortcut, shortcuts app, run, automation, source",
                bundle: .floe,
                comment: "Words that find the Apple Shortcuts setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "remembersSearches",
            String(localized: "Remember searches", bundle: .floe),
            section: String(localized: "Search History", bundle: .floe),
            keywords: String(
                localized: "history, searches, queries, recent, remember, forget, clear, up arrow",
                bundle: .floe,
                comment: "Words that find the Remember searches setting in the settings search, separated by commas."
            ).searchTerms
        ),
        privacy(
            "aiOnThisMacOnly",
            String(localized: "Only use AI that runs on this Mac", bundle: .floe),
            section: String(localized: "Network Access", bundle: .floe),
            keywords: String(
                localized: "ai, local, on device, offline, cloud, private, apple intelligence, ollama, ask",
                bundle: .floe,
                comment: "Words that find the Only use AI that runs on this Mac setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]

    private static func privacy(_ id: String, _ title: String, section: String, keywords: [String]) -> SearchEntry {
        SearchEntry(
            id: "privacy.\(id)",
            title: title,
            pane: .privacy,
            section: section,
            keywords: keywords
        )
    }

    static let generalEntries: [SearchEntry] = [
        .general(
            "toggleHotkey",
            String(localized: "Open Floe", bundle: .floe),
            section: String(localized: "Floe", bundle: .floe, comment: "Floe is the name of this app."),
            keywords: String(
                localized: "hotkey, shortcut, keyboard, global, toggle, show, launcher, summon",
                bundle: .floe,
                comment: "Words that find the Open Floe setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "launchAtLogin",
            String(localized: "Launch at Login", bundle: .floe),
            section: String(localized: "Floe", bundle: .floe, comment: "Floe is the name of this app."),
            keywords: String(
                localized: "startup, start, boot, login item, autostart, open at login",
                bundle: .floe,
                comment: "Words that find the Launch at Login setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "showInDock",
            String(localized: "Show in Dock", bundle: .floe),
            section: String(localized: "Floe", bundle: .floe, comment: "Floe is the name of this app."),
            keywords: String(
                localized: "dock, icon, menu bar, hide, app switcher",
                bundle: .floe,
                comment: "Words that find the Show in Dock setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "popToRootDelay",
            String(localized: "Return to root search", bundle: .floe),
            description: String(localized: "How long a closed launcher keeps the command you had open.", bundle: .floe),
            section: String(localized: "Floe", bundle: .floe, comment: "Floe is the name of this app."),
            keywords: String(
                localized: "pop to root, delay, timeout, reset, close, immediately, seconds, minutes",
                bundle: .floe,
                comment: "Words that find the Return to root search setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "emojiSkinTone",
            String(localized: "Emoji skin tone", bundle: .floe),
            section: String(localized: "Floe", bundle: .floe, comment: "Floe is the name of this app."),
            keywords: String(
                localized: "emoji, skin tone, skin colour, skin color, hand, people",
                bundle: .floe,
                comment: "Words that find the Emoji skin tone setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "checkForUpdates",
            String(localized: "Automatically check for updates", bundle: .floe),
            keywords: String(
                localized: "check for updates, update, updates, automatic, upgrade, new version",
                bundle: .floe,
                comment: "Words that find the Automatically check for updates setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "diagnosticLogging",
            String(localized: "Detailed logging", bundle: .floe),
            description: String(localized: "Writes a log for troubleshooting to ~/Library/Logs/Floe.", bundle: .floe),
            section: String(localized: "Diagnostics", bundle: .floe, comment: "The heading over the logging settings."),
            keywords: String(
                localized: "log, logs, logging, diagnostics, debug, troubleshoot, slow, report",
                bundle: .floe,
                comment: "Words that find the Detailed logging setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "menuBarSearchHotkey",
            String(localized: "Search Menu Bar Items", bundle: .floe),
            description: String(localized: "Find an item in the menu bar and open its menu.", bundle: .floe),
            section: String(localized: "Menu Bar Items", bundle: .floe),
            keywords: String(
                localized: "hotkey, shortcut, keyboard, menu bar, status items, icons",
                bundle: .floe,
                comment: "Words that find the Search Menu Bar Items setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "menuBarSearchAlias",
            String(localized: "Alias", bundle: .floe, comment: "A short name typed in the search to find a command."),
            section: String(localized: "Menu Bar Items", bundle: .floe),
            keywords: String(
                localized: "menu bar, keyword, abbreviation, short name",
                bundle: .floe,
                comment: "Words that find the Alias setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "thawSupport",
            String(localized: "Thaw", bundle: .floe, comment: "Thaw is the name of an app."),
            description: String(localized: "Thaw's actions are in the search: type “thaw” to see them.", bundle: .floe, comment: "The word in quotation marks is typed as it is and stays in English."),
            section: String(localized: "Menu Bar Items", bundle: .floe),
            keywords: String(
                localized: "thaw, hidden items, thaw bar, menu bar manager",
                bundle: .floe,
                comment: "Words that find the Thaw setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
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
        .general(
            "terminalApp",
            AppRole.terminal.title,
            description: AppRole.terminal.detail,
            section: String(localized: "Preferred Apps", bundle: .floe),
            keywords: String(
                localized: "terminal, shell, command line, open in terminal, preferred app, default app",
                bundle: .floe,
                comment: "Words that find the Terminal setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "editorApp",
            AppRole.editor.title,
            description: AppRole.editor.detail,
            section: String(localized: "Preferred Apps", bundle: .floe),
            keywords: String(
                localized: "editor, text editor, code, open in editor, preferred app, default app",
                bundle: .floe,
                comment: "Words that find the Editor setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ] + browserEntries + [
        .general(
            "notesApp",
            AppRole.notes.title,
            description: AppRole.notes.detail,
            section: String(localized: "Preferred Apps", bundle: .floe),
            keywords: String(
                localized: "notes, notes app, apple notes, antinote, new note, quick note, capture, preferred app",
                bundle: .floe,
                comment: "Words that find the Notes setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ] + clipboardEntries + [
        .general(
            "transferSettings",
            String(localized: "Export or import settings", bundle: .floe),
            description: String(localized: "Moves aliases, hotkeys, favorites, appearance and extension preferences to another Mac.", bundle: .floe),
            section: String(localized: "Your Settings", bundle: .floe),
            keywords: String(
                localized: "export, import, backup, transfer, move, file, restore",
                bundle: .floe,
                comment: "Words that find the Export or import settings setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
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
        .general(
            "extensionsFolder",
            String(localized: "Extensions folder", bundle: .floe),
            section: String(localized: "Extensions", bundle: .floe, comment: "The heading over the settings for extensions."),
            keywords: String(
                localized: "finder, directory, location, path, install, show in finder",
                bundle: .floe,
                comment: "Words that find the Extensions folder setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "runtime",
            String(localized: "Runtime", bundle: .floe, comment: "The program that runs extensions."),
            section: String(localized: "Extensions", bundle: .floe, comment: "The heading over the settings for extensions."),
            keywords: String(
                localized: "bun, javascript, node, engine",
                bundle: .floe,
                comment: "Words that find the Runtime setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "scriptsFolder",
            String(localized: "Scripts folder", bundle: .floe),
            section: String(localized: "Script Commands", bundle: .floe),
            keywords: String(
                localized: "script, scripts, script commands, raycast, finder, directory, new script",
                bundle: .floe,
                comment: "Words that find the Scripts folder setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "aiSource",
            String(localized: "Answer AI requests with", bundle: .floe),
            description: String(localized: "Extensions that ask AI a question get their answer from here.", bundle: .floe),
            section: String(localized: "AI", bundle: .floe, comment: "The heading over the settings for artificial intelligence."),
            keywords: String(
                localized: "ai, ask, claude, codex, opencode, pi, openai, openrouter, z.ai, apple intelligence, ollama, lm studio, local, model, llm, assistant, provider",
                bundle: .floe,
                comment: "Words that find the Answer AI requests with setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "aiTool",
            String(localized: "Tool", bundle: .floe, comment: "A command line program that answers AI requests."),
            description: String(localized: "Automatic uses the first one installed: claude, codex, opencode, then pi. Accounts and keys stay in the tool.", bundle: .floe),
            section: String(localized: "AI", bundle: .floe, comment: "The heading over the settings for artificial intelligence."),
            keywords: String(
                localized: "ai, command line, cli, terminal, agent, claude, codex, opencode, pi, automatic",
                bundle: .floe,
                comment: "Words that find the Tool setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "aiAddress",
            String(localized: "Address", bundle: .floe, comment: "The web address of an AI service."),
            section: String(localized: "AI", bundle: .floe, comment: "The heading over the settings for artificial intelligence."),
            keywords: String(
                localized: "ai, api, base url, endpoint, openai, openrouter, z.ai, server, host, service",
                bundle: .floe,
                comment: "Words that find the Address setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "aiModel",
            String(localized: "Model", bundle: .floe, comment: "The AI model that answers."),
            section: String(localized: "AI", bundle: .floe, comment: "The heading over the settings for artificial intelligence."),
            keywords: String(
                localized: "ai, api, model, gpt, openai, opencode, pi",
                bundle: .floe,
                comment: "Words that find the Model setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "aiKey",
            String(localized: "API key", bundle: .floe),
            section: String(localized: "AI", bundle: .floe, comment: "The heading over the settings for artificial intelligence."),
            keywords: String(
                localized: "ai, api, key, token, secret, keychain, openai",
                bundle: .floe,
                comment: "Words that find the API key setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]

    static let quicklinksEntries: [SearchEntry] = [
        .quicklinks(
            "list",
            String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            section: String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            keywords: String(
                localized: "quicklink, keyword, link, name, url, list, edit, delete",
                bundle: .floe,
                comment: "Words that find the Quicklinks setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "new",
            String(localized: "New Quicklink", bundle: .floe),
            section: String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            keywords: String(
                localized: "new, add, create, quicklink",
                bundle: .floe,
                comment: "Words that find the New Quicklink setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "name",
            String(localized: "Name", bundle: .floe, comment: "The label of the field for a name."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "name, title, label",
                bundle: .floe,
                comment: "Words that find the Name setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "keyword",
            String(localized: "Keyword", bundle: .floe, comment: "The word typed in the search to use a quicklink or a snippet."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "keyword, abbreviation, prefix, trigger",
                bundle: .floe,
                comment: "Words that find the Keyword setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "url",
            String(localized: "URL", bundle: .floe, comment: "The label of the field for a web address."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "url, link, address, query, template",
                bundle: .floe,
                comment: "Words that find the URL setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "symbol",
            String(localized: "Symbol", bundle: .floe, comment: "The icon of a quicklink."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "symbol, icon, glyph",
                bundle: .floe,
                comment: "Words that find the Symbol setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "fallback",
            String(localized: "Use as fallback", bundle: .floe),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "fallback, default, search, results",
                bundle: .floe,
                comment: "Words that find the Use as fallback setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "fallbacks",
            String(localized: "Fallbacks", bundle: .floe, comment: "Quicklinks offered under the results of every search."),
            description: String(localized: "Shown under your results when you search.", bundle: .floe),
            section: String(localized: "Fallbacks", bundle: .floe, comment: "Quicklinks offered under the results of every search."),
            keywords: String(
                localized: "fallback, fallbacks, order, reorder, default, results, bottom",
                bundle: .floe,
                comment: "Words that find the Fallbacks setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]

    /// One group per extension: the extension, its preferences, then each command and the
    /// command's preferences. Extensions follow the sidebar's order, by title.
    static func extensionEntries(for commands: [ExtensionCommand]) -> [SearchEntry] {
        var order: [String] = []
        var byExtension: [String: [ExtensionCommand]] = [:]
        for command in commands {
            if byExtension[command.extensionName] == nil {
                order.append(command.extensionName)
            }
            byExtension[command.extensionName, default: []].append(command)
        }
        return order.compactMap { byExtension[$0] }
            .sorted { lhs, rhs in
                guard let left = lhs.first, let right = rhs.first else { return false }
                return left.extensionTitle.localizedCaseInsensitiveCompare(right.extensionTitle) == .orderedAscending
            }
            .flatMap(entries(forExtension:))
    }

    /// The words every extension answers to, beside its own name.
    private static let extensionTerms = String(
        localized: "extension, enabled, enable, disable",
        bundle: .floe,
        comment: "Words that find an extension in the settings search, separated by commas."
    ).searchTerms

    private static func entries(forExtension commands: [ExtensionCommand]) -> [SearchEntry] {
        guard let first = commands.first else { return [] }
        let name = first.extensionName
        let pane = SearchPane(
            page: .extensionPage(name),
            label: SearchPaneLabel(title: first.extensionTitle, icon: first.icon ?? "icon:Terminal", assetsPath: first.assetsPath)
        )

        var entries = [
            SearchEntry(
                id: "extension.\(name)",
                title: first.extensionTitle,
                pane: pane,
                keywords: [name] + extensionTerms + (first.source == .raycast ? ["raycast"] : [])
            ),
        ]
        entries += first.extensionPreferences.map { field in
            SearchEntry(
                id: "extension.\(name).preference.\(field.name)",
                title: field.title,
                descriptionText: field.detail,
                pane: pane,
                section: String(localized: "Preferences", bundle: .floe, comment: "The heading over an extension's own settings."),
                keywords: [field.name]
            )
        }
        for command in commands {
            entries.append(SearchEntry(
                id: "command.\(command.id)",
                title: command.title,
                pane: pane,
                section: String(localized: "Command", bundle: .floe, comment: "The heading a command of an extension is listed under."),
                keywords: [command.name],
                anchor: command.id
            ))
            entries += command.commandPreferences.map { field in
                SearchEntry(
                    id: "command.\(command.id).preference.\(field.name)",
                    title: field.title,
                    descriptionText: field.detail,
                    pane: pane,
                    section: command.title,
                    keywords: [field.name],
                    anchor: command.id
                )
            }
        }
        return entries
    }
}
