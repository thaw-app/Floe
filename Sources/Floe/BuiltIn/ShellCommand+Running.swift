//
//  ShellCommand+Running.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Running a typed command: out of sight in the login shell, or handed to a terminal as a script.
nonisolated extension ShellCommand {
    /// Runs the command in the user's login shell, with the environment of a login, and answers with the line for the HUD.
    @concurrent
    static func run(_ command: String, timeout: TimeInterval = 30) async -> String {
        await finished(command, timeout: timeout).line
    }

    /// The same run, with everything the command printed beside the line: for the window that shows it all.
    @concurrent
    static func finished(_ command: String, in folder: URL? = nil, timeout: TimeInterval = 30) async -> (line: String, output: String) {
        let shell = URL(fileURLWithPath: LoginEnvironment.userShell())
        do {
            let result = try await Shell.run(shell, ["-l", "-c", command], in: folder ?? FileManager.default.homeDirectoryForCurrentUser, environment: LoginEnvironment.current, timeout: timeout, outputLimit: 256 * 1024)
            let output = plain(String(bytes: result.stdout, encoding: .utf8) ?? "")
            let errors = plain(String(bytes: result.stderr, encoding: .utf8) ?? "")
            return (summary(status: result.status, output: output, errors: errors), transcript(status: result.status, output: output, errors: errors))
        } catch {
            return (error.localizedDescription, error.localizedDescription)
        }
    }

    /// Everything a command printed, what it said in error after what it printed, and its code when it failed.
    static func transcript(status: Int32, output: String, errors: String) -> String {
        var parts = [output, errors].map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
        if status != 0 {
            parts.append(String(localized: "The command ended with code \(status).", bundle: .floe, comment: "The placeholder is a number, a command's exit code."))
        }
        return parts.isEmpty ? String(localized: "Done", bundle: .floe, comment: "Said after a command finished and printed nothing.") : parts.joined(separator: "\n\n")
    }

    /// What a finished command comes down to in one line: what it printed first, or that it is done,
    /// or for one that failed what it said and the code it ended with.
    static func summary(status: Int32, output: String, errors: String) -> String {
        func firstLine(_ text: String) -> String? {
            text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        }
        guard status != 0 else {
            return firstLine(output) ?? String(localized: "Done", bundle: .floe, comment: "Said after a command finished and printed nothing.")
        }
        guard let said = firstLine(errors) ?? firstLine(output) else {
            return String(localized: "The command ended with code \(status).", bundle: .floe, comment: "The placeholder is a number, a command's exit code.")
        }
        return String(localized: "\(said) (code \(status))", bundle: .floe, comment: "The first placeholder is what a failed command printed, the second its exit code.")
    }

    /// The command as a script a terminal runs when it is opened with it. It ends in the user's shell, so the window stays.
    static func script(for command: String, shell: String = LoginEnvironment.userShell()) -> String {
        "#!\(shell) -l\ncd ~\n\(command)\nexec \(shell) -l\n"
    }

    /// Clears out the scripts earlier commands were handed to a terminal as. One a terminal may still be reading is kept.
    static func removeScripts(in folder: URL, olderThan limit: Date) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".command") {
            let file = folder.appendingPathComponent(name)
            let written = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
            if let written, written < limit {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Opens the command in the terminal the user chose, or in whichever app opens such scripts.
    @MainActor
    static func runInTerminal(_ command: String, terminal: ResolvedApp?) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-commands", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        removeScripts(in: folder, olderThan: Date().addingTimeInterval(-24 * 60 * 60))
        let file = folder.appendingPathComponent("\(UUID().uuidString).command")
        try Data(script(for: command).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        if let terminal {
            NSWorkspace.shared.open([file], withApplicationAt: terminal.url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }
}
