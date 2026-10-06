//
//  CommandLookup.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Finds extension commands for the App Intents: which ones Shortcuts may offer, which one an
/// identifier stored in a shortcut means, and which ones match what the user typed or said.
/// Plain values in and out, so it runs in a test without the app.
enum CommandLookup {
    /// The commands that are switched on, in scan order: neither their extension nor they themselves are off.
    static func enabled(_ commands: [ExtensionCommand], disabledExtensions: Set<String>, disabledCommands: Set<String> = []) -> [ExtensionCommand] {
        commands.filter { !disabledExtensions.contains($0.extensionName) && !disabledCommands.contains($0.id) }
    }

    /// The command with this "extension/command" identifier, or nil when it was removed or disabled
    /// after the shortcut was made.
    static func command(withID id: String, in commands: [ExtensionCommand]) -> ExtensionCommand? {
        commands.first { $0.id == id }
    }

    /// The commands for these identifiers, in the order asked for; unknown identifiers are skipped.
    static func commands(withIDs ids: [String], in commands: [ExtensionCommand]) -> [ExtensionCommand] {
        ids.compactMap { command(withID: $0, in: commands) }
    }

    /// How well a command matches a query: on its title, or less strongly on its extension's title.
    static func score(query: String, command: ExtensionCommand) -> Int? {
        [Fuzzy.score(query, command.title), Fuzzy.score(query, command.extensionTitle).map { $0 - 10 }]
            .compactMap(\.self)
            .max()
    }

    /// The commands that match a query, best first; ties keep scan order. An empty query matches all.
    static func matching(_ query: String, in commands: [ExtensionCommand]) -> [ExtensionCommand] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return commands }
        return commands.enumerated()
            .compactMap { index, command in score(query: query, command: command).map { (index, command, $0) } }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }
}
