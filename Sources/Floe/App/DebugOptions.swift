//
//  DebugOptions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import ArgumentParser

/// What `Floe` can do from a terminal instead of starting the app; `Floe --help` lists them.
struct DebugOptions: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "Floe", abstract: "With no options, starts the app.")

    @Option(help: ArgumentHelp("Print the ranked root results for a query, for checking aliases and ranking.", valueName: "query"))
    var search: String?

    @Flag(help: "Time laying out each settings page off screen. FLOE_BENCH_DUMP=<folder> saves what each page looks like.")
    var benchSettings = false

    @Flag(help: "Time the catalog scan and each keystroke of the queries after it, drawn off screen.")
    var benchSearch = false

    @Flag(help: "Print a fingerprint of each command's icon and how much of it is drawn. FLOE_ICON_DUMP=<folder> also writes the PNGs.")
    var iconCheck = false

    @Flag(name: .customLong("menubar"), help: "List the menu bar items Floe can open, ranked for the query after it if there is one.")
    var menuBar = false

    @Option(help: ArgumentHelp("Draw the launcher's root, compact and menu bar views off screen and save them.", valueName: "folder"))
    var panelSnapshot: String?

    @Flag(help: "Choose one of the lines on standard input in a search panel and print it. Exits 1 if nothing is chosen. FLOE_PICK_AUTO=1 prints the first match without showing the panel; FLOE_PICK_SNAPSHOT=<file> saves a picture of the panel instead.")
    var pick = false

    @Option(help: ArgumentHelp("With --pick, the search field's placeholder.", valueName: "text"))
    var prompt: String?

    @Option(help: ArgumentHelp("With --pick, the text the search field starts with.", valueName: "text"))
    var query: String?

    @Flag(help: "With --pick, print the chosen line's position in the input, counting from 0, instead of its text.")
    var index = false

    @Flag(help: "Show the settings window in a process of its own, which ends when the window closes. The app starts it this way. FLOE_SETTINGS_CLOSE_AFTER=<seconds> closes the window by itself.")
    var settings = false

    @Flag(help: .hidden)
    var panel = false

    @Option(help: ArgumentHelp("With --settings, the page to open: general, applications, quicklinks, snippets, store, appearance, privacy or about.", valueName: "page"))
    var page: String?

    @Option(name: .customLong("extension"), help: ArgumentHelp("With --settings, the extension whose page to open.", valueName: "name"))
    var extensionName: String?

    @Option(parsing: .upToNextOption, help: ArgumentHelp("Run a command without UI and report the first view it renders.", valueName: "extension> <command"))
    var selftest: [String] = []

    /// The menu bar query, and whatever macOS or Xcode adds to the command line.
    @Argument(parsing: .allUnrecognized, help: .hidden)
    var rest: [String] = []

    func validate() throws {
        guard selftest.isEmpty || selftest.count == 2 else {
            throw ValidationError("--selftest takes an extension and a command.")
        }
        guard pick || (prompt == nil && query == nil && !index) else {
            throw ValidationError("--prompt, --query and --index only go with --pick.")
        }
        guard settings || (page == nil && extensionName == nil) else {
            throw ValidationError("--page and --extension only go with --settings.")
        }
        guard page == nil || extensionName == nil else {
            throw ValidationError("--page and --extension name two pages; give one.")
        }
        if let page, SettingsPage(id: page) == nil {
            throw ValidationError("Settings has no page called \(page).")
        }
    }

    /// The page --settings opens; nil is the page Settings starts on.
    var settingsPage: SettingsPage? {
        if let extensionName {
            return .extensionPage(extensionName)
        }
        return page.flatMap(SettingsPage.init(id:))
    }
}
