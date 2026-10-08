//
//  ShellCommand+Saving.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Keeping a typed command as a script command in the user's scripts folder.
nonisolated extension ShellCommand {
    /// The text of a script command that runs the command, for the user's scripts folder.
    static func savedScript(title: String, command: String, shell: String = LoginEnvironment.userShell()) -> String {
        """
        #!\(shell) -l

        # @raycast.schemaVersion 1
        # @raycast.title \(title.split(whereSeparator: \.isNewline).joined(separator: " "))
        # @raycast.mode silent
        # @raycast.packageName Commands
        # @raycast.icon 💻

        \(command)

        """
    }

    /// A file name for a saved command that no file in the folder has yet: the title in plain letters, numbered when taken.
    static func fileName(for title: String, taken: Set<String>) -> String {
        let letters = title.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
        let slug = String(letters).split(separator: "-").joined(separator: "-")
        let base = slug.isEmpty ? "command" : String(slug.prefix(40))
        var name = "\(base).sh"
        var number = 2
        while taken.contains(name) {
            name = "\(base)-\(number).sh"
            number += 1
        }
        return name
    }

    /// Writes the command into the scripts folder as a script command, and answers with the file.
    static func save(_ command: String, as title: String, in folder: URL = Paths.scripts, shell: String = LoginEnvironment.userShell()) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let file = folder.appendingPathComponent(fileName(for: title, taken: taken))
        try Data(savedScript(title: title, command: command, shell: shell).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }
}
