//
//  ShellAliases.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Synchronization

/// The aliases of the user's shell, so `> gs` runs what `gs` runs in their terminal. Commands run in a shell
/// that reads none, since one that does prints its greeting into the output: they are asked for once and put back.
nonisolated enum ShellAliases {
    /// The aliases in what `alias` printed: `gs='git status'` from zsh, `alias gs='git status'` from bash.
    /// Anything else an interactive shell printed on the way is left out.
    static func parse(_ output: String) -> [String: String] {
        var aliases: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let entry = line.hasPrefix("alias ") ? line.dropFirst(6) : line
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let name = entry[..<equals]
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || "_.:+-".contains($0) }) else { continue }
            var value = String(entry[entry.index(after: equals)...])
            // A form of quoting with escapes of its own. Rare, and safer left alone than half understood.
            guard !value.hasPrefix("$'") else { continue }
            if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
            } else if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            aliases[String(name)] = value
        }
        return aliases
    }

    /// The command with its first word put back as what it stands for, as often as a shell would: an alias may
    /// name another, and one that names itself is not gone round again.
    static func expanded(_ command: String, with aliases: [String: String]) -> String {
        var command = command
        var used = Set<String>()
        while let word = command.split(separator: " ", maxSplits: 1).first.map(String.init),
              let value = aliases[word], used.insert(word).inserted
        {
            command = value + command.dropFirst(word.count)
        }
        return command
    }

    private static let loaded = Mutex<[String: String]?>(nil)

    /// The user's aliases, asked of their shell the first time and kept. Empty when the shell does not answer
    /// in five seconds: a slow shell is not asked again at every command.
    @concurrent
    static func table() async -> [String: String] {
        if let known = loaded.withLock({ $0 }) {
            return known
        }
        let shell = URL(fileURLWithPath: LoginEnvironment.userShell())
        let result = try? await Shell.run(shell, ["-i", "-c", "alias"], environment: LoginEnvironment.current, timeout: 5, outputLimit: 256 * 1024)
        let aliases = result.map { parse(String(bytes: $0.stdout, encoding: .utf8) ?? "") } ?? [:]
        loaded.withLock { $0 = aliases }
        return aliases
    }
}
