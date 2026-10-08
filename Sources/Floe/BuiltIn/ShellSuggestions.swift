//
//  ShellSuggestions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Synchronization

/// A command line in the results: the one being typed, or one offered under it.
nonisolated struct ShellRow: Hashable, Sendable {
    enum Origin: String, Sendable {
        /// What the user typed after the prefix, or a search recognized as a command. Return runs it.
        case typed
        /// A whole command from the shell's history. Return runs it.
        case history
        /// The typed command with a program's name or a path finished. Return puts it in the search to go on from.
        case completion
    }

    let text: String
    let origin: Origin
}

extension ShellRow.Origin {
    /// The kind shown beside the row's title.
    var label: String {
        switch self {
        case .typed: String(localized: "Shell", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a command for the command line.")
        case .history: String(localized: "History", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a command the user ran before.")
        case .completion: String(localized: "Complete", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a command that Tab or Return finishes typing.")
        }
    }

    var symbol: String {
        switch self {
        case .typed: "terminal"
        case .history: "clock.arrow.circlepath"
        case .completion: "arrow.right.to.line"
        }
    }
}

/// What Return does on a row of the shell. Its button, the keys, the menu and the bottom bar all read this one answer.
enum ShellAction {
    case run(String, terminal: ResolvedApp?)
    /// Puts the row's text into the search, to go on typing from.
    case complete(ShellRow)
    case quit(RunningProcess)

    var title: String {
        switch self {
        case .run: String(localized: "Run", bundle: .floe, comment: "A verb on a button: run the shortcut or script.")
        case .complete: String(localized: "Complete", bundle: .floe, comment: "A verb on a button: finish typing the command as the row has it.")
        case .quit: String(localized: "Quit", bundle: .floe, comment: "An action that quits a running app.")
        }
    }
}

extension RootItem {
    /// What Return does when the row is one of the shell's, or nil for any other row.
    var shellAction: ShellAction? {
        switch self {
        case let .shell(row, terminal):
            if row.origin == .completion {
                .complete(row)
            } else {
                .run(row.text, terminal: terminal)
            }
        case let .process(process): .quit(process)
        default: nil
        }
    }
}

/// What to offer for the text typed after the prefix.
nonisolated enum ShellSuggestions {
    static let limit = 7

    /// `history` is newest first. `programs` are the names on the PATH, sorted. `entries` lists a folder as names, a folder's ending in a slash.
    static func suggestions(
        for typed: String, history: [String], programs: [String], apps: [String] = [], hosts: [String] = [], entries: (String) -> [String]
    ) -> [ShellRow] {
        var found = (names(for: typed, apps: apps, hosts: hosts) + paths(for: typed, entries: entries)).map { ShellRow(text: $0, origin: .completion) }
        let started = typed.trimmingCharacters(in: .whitespaces)
        let earlier = history.filter { $0 != started }
        found += earlier.filter { $0.hasPrefix(started) }.prefix(5).map { ShellRow(text: $0, origin: .history) }
        if !started.isEmpty {
            // A program's name is finished only while it is the one word typed.
            if !started.contains(" "), !typed.hasSuffix(" ") {
                found += programs.filter { $0.hasPrefix(started) && $0 != started }.prefix(3).map { ShellRow(text: $0 + " ", origin: .completion) }
            }
            let anywhere = earlier.filter { !$0.hasPrefix(started) && $0.localizedCaseInsensitiveContains(started) }
            found += anywhere.prefix(3).map { ShellRow(text: $0, origin: .history) }
        }
        var seen = Set<String>()
        return Array(found.filter { seen.insert($0.text).inserted }.prefix(limit))
    }

    /// The typed line finished with a name Floe already knows: an application after `open -a`, a host after `ssh` or `scp`.
    static func names(for typed: String, apps: [String], hosts: [String]) -> [String] {
        let words = typed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let program = words.first else { return [] }
        if program == "open", let flag = words.firstIndex(of: "-a") {
            // An application's name may have spaces in it, so everything after the flag is its start.
            let start = words[(flag + 1)...].joined(separator: " ")
            let line = words[...flag].joined(separator: " ")
            return apps.filter { $0.lowercased().hasPrefix(start.lowercased()) && $0.lowercased() != start.lowercased() }
                .prefix(5).map { line + " " + ($0.contains(" ") ? "\"\($0)\"" : $0) }
        }
        guard program == "ssh" || program == "scp", !hosts.isEmpty else { return [] }
        let start = typed.hasSuffix(" ") ? "" : (words.count > 1 ? words.last ?? "" : "")
        guard typed.hasSuffix(" ") || words.count > 1, !start.hasPrefix("-") else { return [] }
        let line = String(typed.dropLast(start.count))
        return hosts.filter { $0.hasPrefix(start) && $0 != start }.prefix(5).map { line + $0 }
    }

    /// The typed line with its last word, a path, finished by each entry of the folder that starts as it does.
    static func paths(for typed: String, entries: (String) -> [String]) -> [String] {
        guard let word = typed.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init),
              word.hasPrefix("/") || word.hasPrefix("~") || word.hasPrefix("./") || word.hasPrefix("../") else { return [] }
        let cut = word.lastIndex(of: "/").map { word.index(after: $0) } ?? word.endIndex
        let folder = String(word[..<cut])
        let start = String(word[cut...])
        guard !folder.isEmpty else { return [] }
        let line = String(typed.dropLast(word.count))
        return entries(folder)
            .filter { $0.lowercased().hasPrefix(start.lowercased()) && ($0.hasPrefix(".") == start.hasPrefix(".")) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(5)
            .map { line + folder + $0.replacingOccurrences(of: " ", with: "\\ ") }
    }

    /// The names in a folder as they are on disk, a folder's with a slash after it. Empty for what cannot be read.
    static func entriesOnDisk(_ folder: String) -> [String] {
        let path = (folder as NSString).expandingTildeInPath
        let base = path.hasPrefix("/") ? path : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path).path
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
        return names.map { name in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: (base as NSString).appendingPathComponent(name), isDirectory: &isFolder)
            return isFolder.boolValue ? name + "/" : name
        }
    }

    private static let programNames = TimedCache<Int, [String]>()

    /// Every program on the login PATH, by name. Listed once: the folders are walked at the first use.
    static func programsOnPath() -> [String] {
        programNames.value(for: 0) {
            let path = LoginEnvironment.current["PATH"] ?? LoginEnvironment.augmentedPath(nil)
            var names = Set<String>()
            for folder in path.split(separator: ":") {
                names.formUnion((try? FileManager.default.contentsOfDirectory(atPath: String(folder))) ?? [])
            }
            return names.filter { !$0.hasPrefix(".") }.sorted()
        }
    }
}

/// The commands the user ran in their shell, read from its history file. Nothing is copied out of it or kept on disk.
nonisolated enum ShellHistory {
    /// How much of the file's end is read: the newest commands are there.
    static let tail = 256 * 1024

    /// The commands in a history file's text, newest first and each once. zsh may put a time before a
    /// command (`: 1700000000:0;ls`); a command carried over several lines is left out.
    static func commands(in text: String) -> [String] {
        var commands: [String] = []
        var seen = Set<String>()
        var continues = false
        for line in text.split(whereSeparator: \.isNewline) {
            let wasContinuing = continues
            continues = line.hasSuffix("\\")
            guard !wasContinuing, !continues else { continue }
            var command = Substring(line)
            if command.hasPrefix(": "), let end = command.firstIndex(of: ";") {
                command = command[command.index(after: end)...]
            }
            let trimmed = command.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 300 else { continue }
            commands.append(trimmed)
        }
        return commands.reversed().filter { seen.insert($0).inserted }
    }

    static func files(environment: [String: String] = LoginEnvironment.current, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let named = environment["HISTFILE"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return ([named].compactMap(\.self) + [".zsh_history", ".bash_history"].map { home.appendingPathComponent($0) })
    }

    private struct Read {
        var file: URL
        var modified: Date
        var commands: [String]
    }

    private static let last = Mutex<Read?>(nil)

    /// The history of the first file there is, read again only when the file has changed.
    static func commands(from files: [URL] = files()) -> [String] {
        guard let file = files.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else { return [] }
        if let read = last.withLock({ $0 }), read.file == file, read.modified == modified {
            return read.commands
        }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tail) ? size - UInt64(tail) : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        // zsh writes some characters in a form of its own; what cannot be read as text is replaced, not dropped.
        // swiftlint:disable:next optional_data_string_conversion
        var lines = String(decoding: data, as: UTF8.self)
        if size > UInt64(tail), let firstBreak = lines.firstIndex(where: \.isNewline) {
            // The read began in the middle of a line.
            lines = String(lines[lines.index(after: firstBreak)...])
        }
        let commands = commands(in: lines)
        last.withLock { $0 = Read(file: file, modified: modified, commands: commands) }
        return commands
    }
}
