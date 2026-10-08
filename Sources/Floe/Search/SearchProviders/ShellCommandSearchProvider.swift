//
//  ShellCommandSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The prefix and a command lead the results with the row that runs it, and what it could become under it.
/// A search without the prefix that reads as a command gets the row under everything else.
struct ShellCommandSearchProvider: SearchProvider {
    var isProgram: @Sendable (String) -> Bool = { ShellCommand.isProgram($0) }
    var history: @Sendable () -> [String] = { ShellHistory.commands() }
    var programs: @Sendable () -> [String] = { ShellSuggestions.programsOnPath() }
    var entries: @Sendable (String) -> [String] = { ShellSuggestions.entriesOnDisk($0) }

    func contribution(for context: SearchContext) -> SearchContribution {
        let shell = context.shell
        let prefix = shell.runs ? shell.prefix : nil
        let terminal = context.preferredApps.first { $0.role == .terminal }?.app
        let result: (ShellRow) -> RootResult = { RootResult(item: .shell($0, terminal: terminal), section: nil) }
        if let typed = ShellCommand.typed(in: context.query, prefix: prefix) {
            var rows = ShellCommand.command(in: context.query, prefix: prefix).map { [ShellRow(text: $0, origin: .typed)] } ?? []
            if shell.suggests {
                rows += ShellSuggestions.suggestions(
                    for: typed, history: history(), programs: programs(), apps: context.apps.map(\.name), hosts: context.sshHosts.map(\.alias), entries: entries
                )
            }
            return SearchContribution(pinned: rows.map(result))
        }
        // A guess is kept under everything the search found: Return runs it only when nothing else answered.
        guard shell.runs, shell.recognizes, ShellCommand.reads(asACommand: context.trimmed, isProgram: isProgram) else { return SearchContribution() }
        return SearchContribution(appended: [result(ShellRow(text: context.trimmed, origin: .typed))])
    }
}
