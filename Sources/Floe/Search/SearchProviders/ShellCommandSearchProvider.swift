//
//  ShellCommandSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The prefix and a command lead the results with the row that runs it, and what it could become under it.
/// A search without the prefix that reads as a command is offered among the fallbacks (see `guess`).
struct ShellCommandSearchProvider: SearchProvider {
    /// The suggestions read snapshots the store keeps, so the reads follow behind the typing
    /// off the main actor. A test hands over its own instead.
    var isProgram: @Sendable (String) -> Bool = { ShellCommand.isProgram($0) }
    var history: @Sendable () -> [String] = { ShellSnapshots.shared.history() }
    var programs: @Sendable () -> [String] = { ShellSnapshots.shared.programs() }
    var entries: @Sendable (String) -> [String] = { ShellSnapshots.shared.entries($0) }

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
        return SearchContribution()
    }

    /// The text run as a command line, when it reads as one: a fallback, so Return runs it only when nothing else answered.
    func guess(for context: SearchContext) -> RootItem? {
        let shell = context.shell
        guard shell.runs, shell.recognizes, ShellCommand.typed(in: context.query, prefix: shell.prefix) == nil,
              ShellCommand.reads(asACommand: context.trimmed, isProgram: isProgram) else { return nil }
        let terminal = context.preferredApps.first { $0.role == .terminal }?.app
        return .shell(ShellRow(text: context.trimmed, origin: .typed), terminal: terminal)
    }
}
