//
//  ShellCommand.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The character that makes the rest of a search a shell command. Chosen in Settings.
nonisolated enum CommandPrefix: String, Codable, CaseIterable, Identifiable, Sendable {
    case greaterThan = ">"
    case dollar = "$"
    case exclamation = "!"

    var id: String {
        rawValue
    }
}

/// How the launcher treats shell commands, as Settings has it. A file from before a switch existed reads as its default.
nonisolated struct ShellSettings: Codable, Equatable, Sendable {
    /// Whether a search that starts with the prefix is offered as a shell command.
    var runs = true
    var prefix = CommandPrefix.greaterThan
    /// Whether a search that reads as a command is offered as one without the prefix.
    var recognizes = true
    /// Whether earlier commands, programs and paths are offered under a command being typed.
    var suggests = true

    init() {
        // The defaults above.
    }

    /// Nothing offered: no command behind the prefix, none recognized, nothing suggested.
    static var off: ShellSettings {
        var settings = ShellSettings()
        settings.runs = false
        settings.recognizes = false
        settings.suggests = false
        return settings
    }

    init(from decoder: Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)
        runs = try stored.decodeIfPresent(Bool.self, forKey: .runs) ?? true
        prefix = try stored.decodeIfPresent(CommandPrefix.self, forKey: .prefix) ?? .greaterThan
        recognizes = try stored.decodeIfPresent(Bool.self, forKey: .recognizes) ?? true
        suggests = try stored.decodeIfPresent(Bool.self, forKey: .suggests) ?? true
    }
}

/// A command typed into the launcher after the prefix: `> pkill -f debug/ThawNotch`.
nonisolated enum ShellCommand {
    /// The command in a search, or nil when the search is not one: no prefix, or nothing after it.
    /// What follows the prefix as it was typed, spaces at its end kept, or nil for a search without the prefix.
    static func typed(in query: String, prefix: CommandPrefix?) -> String? {
        guard let prefix, query.hasPrefix(prefix.rawValue) else { return nil }
        let rest = query.dropFirst(prefix.rawValue.count)
        // With the dollar sign as the prefix, a number straight after it is an amount: "$100 to eur" is the calculator's.
        if prefix == .dollar, rest.first?.isNumber == true {
            return nil
        }
        return String(rest.drop { $0 == " " })
    }

    static func command(in query: String, prefix: CommandPrefix?) -> String? {
        guard let command = typed(in: query, prefix: prefix)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return command.isEmpty ? nil : command
    }

    /// Whether a search without the prefix reads as a command, the way Warp tells a command from a sentence:
    /// its first word is a program on this Mac, and what follows has the grammar of a command line in it:
    /// a flag, a path, a pipe or a redirection. `pkill -f debug/ThawNotch` is one; `find my keys` and `git status` are not.
    static func reads(asACommand query: String, isProgram: (String) -> Bool) -> Bool {
        let words = query.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 2, let program = words.first else { return false }
        let plain = program.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || "._+-".contains($0)) }
        guard plain, program.first?.isLetter == true else { return false }
        let hasGrammar = words.dropFirst().contains { word in
            let isFlag = word.hasPrefix("-") && word.dropFirst().first.map { $0.isLetter || $0 == "-" } == true
            let isPath = word.contains("/") || word.hasPrefix("~") || word.hasPrefix("./")
            return isFlag || isPath || ["|", "&&", "||", ">", ">>", "<"].contains(String(word))
        }
        return hasGrammar && isProgram(String(program))
    }

    /// The programs found so far by name: looking one up walks the PATH, and the search asks at every key.
    private static let knownPrograms = TimedCache<String, Bool>()

    static func isProgram(_ name: String) -> Bool {
        knownPrograms.value(for: name) { LoginEnvironment.which(name) != nil }
    }

    /// Whether the command has to be typed at: `sudo` asks for a password, and there is nowhere to give one here.
    static func needsATerminal(_ command: String) -> Bool {
        command.split(separator: " ").first.map { $0 == "sudo" } ?? false
    }

    /// The first word of a command, the program it runs, past a leading `sudo`.
    static func program(of command: String) -> String? {
        let words = command.split(separator: " ")
        return (words.first == "sudo" ? words.dropFirst().first : words.first).map(String.init)
    }

    /// The command that prints a program's manual as plain text: `man` writes for a terminal, bold as letters typed twice.
    static func manual(for page: String) -> String {
        "MANWIDTH=90 man -P cat \(page) 2>&1 | col -bx"
    }

    /// A command to read and not to act on: `man rsync` is run as the text of the manual, for the window.
    static func asReading(_ command: String) -> String? {
        let words = command.split(separator: " ")
        guard words.first == "man", words.count >= 2, !command.contains("|") else { return nil }
        return manual(for: words.dropFirst().joined(separator: " "))
    }

    /// Text as a terminal would colour it, with the colours taken out.
    static func plain(_ text: String) -> String {
        text.replacing(/\u{1B}\[[0-9;]*[A-Za-z]/, with: "")
    }

    /// The command that shows a program's common uses, for a Mac that has `tldr`.
    static func examples(for program: String) -> String {
        "tldr \(program)"
    }
}
