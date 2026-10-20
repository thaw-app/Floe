//
//  AppleShortcuts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Foundation
import Subprocess
import System

/// A shortcut the user made in Apple's Shortcuts app. Floe knows its name and nothing of what it does.
nonisolated struct AppleShortcut: Hashable, Identifiable, Sendable {
    let name: String
    /// What the Shortcuts tool calls it. A rename keeps it, so a run, a favorite and the usage record do too.
    let identifier: String

    var id: String {
        "shortcut:\(identifier)"
    }
}

/// Reads what `shortcuts list --show-identifiers` prints: one "Name (identifier)" per line.
nonisolated enum AppleShortcutList {
    static func parse(_ output: String) -> [AppleShortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { shortcut(in: String($0)) }.uniqued(on: \.identifier)
    }

    /// A name may hold parentheses of its own, so the identifier is the last pair on the line.
    /// A line without one is left out: there would be nothing to run it by.
    static func shortcut(in line: String) -> AppleShortcut? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else { return nil }
        let identifier = String(line[line.index(after: open) ..< line.index(before: line.endIndex)])
        let name = line[..<open].trimmingCharacters(in: .whitespaces)
        guard UUID(uuidString: identifier) != nil, !name.isEmpty else { return nil }
        return AppleShortcut(name: name, identifier: identifier)
    }
}

/// How one run of the Shortcuts tool ended.
nonisolated struct ShortcutsToolResult: Equatable, Sendable {
    var succeeded: Bool
    var output = ""
    var errorOutput = ""
}

/// The command line tool that comes with Shortcuts. Tests pass their own, so none lists or runs a real shortcut.
nonisolated struct ShortcutsTool: Sendable {
    /// Runs the tool with these arguments and waits for it to end.
    var run: @Sendable ([String]) async -> ShortcutsToolResult

    static let path = "/usr/bin/shortcuts"
    /// How much of the tool's text is kept. A list of names is far shorter.
    static let outputLimit = 4 * 1024 * 1024
    /// How much of a failure's last line the HUD shows.
    static let failureLimit = 200

    static let system = ShortcutsTool { await launch($0) }

    /// The user's shortcuts in the tool's order; nil when the tool could not be asked.
    @concurrent
    func list() async -> [AppleShortcut]? {
        let result = await run(["list", "--show-identifiers"])
        return result.succeeded ? AppleShortcutList.parse(result.output) : nil
    }

    /// Runs a shortcut by its identifier, with no input. Returns the line for the HUD when it failed.
    @concurrent
    func run(_ shortcut: AppleShortcut) async -> String? {
        let result = await run(["run", shortcut.identifier])
        guard !result.succeeded else { return nil }
        guard let line = Self.lastLine(result.errorOutput) else {
            return String(localized: "\(shortcut.name) failed. Open it in Shortcuts to see why.", bundle: .floe, comment: "The placeholder is the name of a shortcut, and Shortcuts is the app.")
        }
        return String(localized: "\(shortcut.name) failed: \(line)", bundle: .floe, comment: "The first placeholder is the name of a shortcut and the second is what the Shortcuts tool said.")
    }

    /// What runs a shortcut by its name with a file as its input. The name comes after "--", so one that starts with a hyphen is not read as an option.
    static func arguments(running name: String, inputFile: String) -> [String] {
        ["run", "--input-path", inputFile, "--", name]
    }

    /// Runs a shortcut by name with a text as its input. The tool takes input as a file, so the text is in one while it runs.
    /// Returns the line for the HUD when it failed.
    @concurrent
    func run(named name: String, input: String) async -> String? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-shortcut-input-\(UUID().uuidString).txt")
        do {
            try Data(input.utf8).write(to: file)
        } catch {
            return error.localizedDescription
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let result = await run(Self.arguments(running: name, inputFile: file.path))
        guard !result.succeeded else { return nil }
        guard let line = Self.lastLine(result.errorOutput) else {
            return String(localized: "\(name) failed. Open it in Shortcuts to see why.", bundle: .floe, comment: "The placeholder is the name of a shortcut, and Shortcuts is the app.")
        }
        return String(localized: "\(name) failed: \(line)", bundle: .floe, comment: "The first placeholder is the name of a shortcut and the second is what the Shortcuts tool said.")
    }

    /// Shows a shortcut in the Shortcuts app. The tool's "view" takes a name, so "--" keeps a
    /// name that starts with a hyphen from being read as an option.
    @concurrent
    func view(_ shortcut: AppleShortcut) async -> String? {
        let result = await run(["view", "--", shortcut.name])
        guard !result.succeeded else { return nil }
        guard let line = Self.lastLine(result.errorOutput) else {
            return String(localized: "Couldn't open \(shortcut.name) in Shortcuts. Open the Shortcuts app and look for it there.", bundle: .floe, comment: "The placeholder is the name of a shortcut, and Shortcuts is the app.")
        }
        return String(localized: "Couldn't open \(shortcut.name) in Shortcuts: \(line)", bundle: .floe, comment: "The first placeholder is the name of a shortcut and the second is what the Shortcuts tool said.")
    }

    /// The last line that says something, cut to what a HUD can show.
    static func lastLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
        return line.map { $0.count > failureLimit ? $0.prefix(failureLimit) + "…" : $0 }
    }

    /// No timeout: a shortcut may wait for the user or work for minutes, and it is Shortcuts' to end.
    /// Only the list's text is kept. What a shortcut prints is dropped.
    @concurrent
    private static func launch(_ arguments: [String]) async -> ShortcutsToolResult {
        do {
            guard arguments.first == "list" else {
                let result = try await Subprocess.run(
                    .path(FilePath(path)),
                    arguments: Arguments(arguments),
                    output: .discarded,
                    error: .string(limit: outputLimit)
                )
                return ShortcutsToolResult(succeeded: result.terminationStatus.isSuccess, errorOutput: result.standardError)
            }
            let result = try await Subprocess.run(
                .path(FilePath(path)),
                arguments: Arguments(arguments),
                output: .string(limit: outputLimit),
                error: .string(limit: outputLimit)
            )
            return ShortcutsToolResult(
                succeeded: result.terminationStatus.isSuccess,
                output: result.standardOutput,
                errorOutput: result.standardError
            )
        } catch {
            return ShortcutsToolResult(succeeded: false, errorOutput: error.localizedDescription)
        }
    }
}

/// The shortcuts Floe last heard of, and the runs it starts. Nothing is listed or run until it is asked to.
@MainActor
final class AppleShortcutLibrary {
    var tool = ShortcutsTool.system
    /// The last list the tool gave. The search reads this and never waits for the tool.
    private(set) var shortcuts: [AppleShortcut] = []
    private var loading: Task<Void, Never>?
    /// Bumped when the switch goes off, so a list that arrives afterwards is dropped.
    private var generation = 0

    nonisolated init() {
        // Nothing is read until the first refresh.
    }

    /// Asks the tool again in the background, one request at a time, and keeps the list it has until
    /// the new one is in. With the switch off the tool is not started and the list is emptied.
    @discardableResult
    func refresh(isOn: Bool, onChange: @escaping () -> Void) -> Task<Void, Never>? {
        guard isOn else {
            generation += 1
            loading?.cancel()
            loading = nil
            shortcuts = []
            return nil
        }
        if let loading {
            return loading
        }
        let started = generation
        let task = Task { [tool] in
            let listed = await tool.list()
            guard started == self.generation else { return }
            self.loading = nil
            guard let listed else {
                // The last list stays in place. No shortcut's name is logged, here or anywhere.
                Log.catalog.warning("The Shortcuts tool gave no list of shortcuts")
                return
            }
            guard listed != self.shortcuts else { return }
            self.shortcuts = listed
            onChange()
        }
        loading = task
        return task
    }

    /// Starts a run and returns at once. Each run is its own task, so two of one shortcut may overlap,
    /// and none ends because the panel closed. `showHUD` hears only of a failure.
    @discardableResult
    func run(_ shortcut: AppleShortcut, showHUD: @escaping (String) -> Void) -> Task<Void, Never> {
        Task { [tool] in
            if let failure = await tool.run(shortcut) {
                showHUD(failure)
            }
        }
    }

    /// Starts a run of the shortcut by that name, with a text as its input. `showHUD` hears only of a failure.
    @discardableResult
    func run(named name: String, input: String, showHUD: @escaping (String) -> Void) -> Task<Void, Never> {
        Task { [tool] in
            if let failure = await tool.run(named: name, input: input) {
                showHUD(failure)
            }
        }
    }

    @discardableResult
    func openInShortcuts(_ shortcut: AppleShortcut, showHUD: @escaping (String) -> Void) -> Task<Void, Never> {
        Task { [tool] in
            if let failure = await tool.view(shortcut) {
                showHUD(failure)
            }
        }
    }
}
