//
//  ScriptCommands.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Foundation

/// How a script command shows its output, as `@raycast.mode` declares it.
nonisolated enum ScriptMode: String, Sendable {
    case fullOutput
    case compact
    case silent
    case inline
}

/// One declared argument (`@raycast.argument1` … `@raycast.argument3`), as JSON.
nonisolated struct ScriptArgument: Sendable, Hashable {
    let placeholder: String
    let optional: Bool
}

/// Why a file in the Scripts folder is not a runnable command. A dedicated error type so the
/// settings pane can list failures without passing message strings around.
nonisolated enum ScriptParseError: Error, LocalizedError, Sendable, Hashable {
    case unreadable
    case missingSchemaVersion
    case unsupportedSchemaVersion(String)
    case missingTitle
    case unsupportedMode(String)
    case invalidArgument(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "The file couldn't be read as text.", bundle: .floe)
        case .missingSchemaVersion:
            String(localized: "Missing @raycast.schemaVersion. Add `# @raycast.schemaVersion 1`.", bundle: .floe, comment: "The text between the backticks, and the word that starts with @raycast, are typed into a script as they are.")
        case let .unsupportedSchemaVersion(version):
            String(localized: "Unsupported @raycast.schemaVersion \(version). Floe reads version 1.", bundle: .floe, comment: "The word that starts with @raycast is typed into a script as it is, and the placeholder is the version the script names.")
        case .missingTitle:
            String(localized: "Missing @raycast.title. Add `# @raycast.title My Script`.", bundle: .floe, comment: "The word that starts with @raycast is typed into a script as it is.")
        case let .unsupportedMode(mode):
            String(localized: "Unknown @raycast.mode \(mode). Use fullOutput, compact, silent or inline.", bundle: .floe, comment: "The word that starts with @raycast and the four mode names are typed into a script as they are.")
        case let .invalidArgument(index):
            String(localized: "@raycast.argument\(index) isn't valid JSON with a placeholder, e.g. {\"type\": \"text\", \"placeholder\": \"Name\"}.", bundle: .floe, comment: "The word that starts with @raycast and the keys in the braces are typed into a script as they are, and the placeholder is the number of the argument.")
        }
    }
}

/// A Raycast-compatible script command: an executable file in the Scripts folder with
/// `@raycast.*` metadata in its leading comments.
nonisolated struct ScriptCommand: Identifiable, Sendable, Hashable {
    let file: URL
    let title: String
    let packageName: String?
    let mode: ScriptMode
    let needsConfirmation: Bool
    let icon: String?
    let arguments: [ScriptArgument]

    var id: String {
        "script/\(file.lastPathComponent)"
    }

    var displayPackage: String {
        packageName ?? String(localized: "Script Command", bundle: .floe, comment: "What a script command is called where it names no package.")
    }

    /// Reads one file's metadata. schemaVersion and title are required; mode defaults to
    /// fullOutput; up to three arguments are kept.
    static func parse(file: URL) -> Result<ScriptCommand, ScriptParseError> {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .failure(.unreadable)
        }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let range = line.range(of: "@raycast.") else { continue }
            let rest = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            var end = rest.startIndex
            while end < rest.endIndex, rest[end].isLetter {
                end = rest.index(after: end)
            }
            while end < rest.endIndex, rest[end].isNumber {
                end = rest.index(after: end)
            }
            let key = String(rest[..<end]).lowercased()
            let value = String(rest[end...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, values[key] == nil else { continue }
            values[key] = value
        }
        guard let schema = values["schemaversion"], !schema.isEmpty else {
            return .failure(.missingSchemaVersion)
        }
        guard schema == "1" else {
            return .failure(.unsupportedSchemaVersion(schema))
        }
        guard let title = values["title"], !title.isEmpty else {
            return .failure(.missingTitle)
        }
        let mode: ScriptMode
        if let raw = values["mode"], !raw.isEmpty {
            guard let parsed = ScriptMode(rawValue: raw) else {
                return .failure(.unsupportedMode(raw))
            }
            mode = parsed
        } else {
            mode = .fullOutput
        }
        var arguments: [ScriptArgument] = []
        for index in 1 ... 3 {
            guard let raw = values["argument\(index)"], !raw.isEmpty else { continue }
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let placeholder = json["placeholder"] as? String, !placeholder.isEmpty
            else {
                return .failure(.invalidArgument(index))
            }
            arguments.append(ScriptArgument(placeholder: placeholder, optional: (json["optional"] as? Bool) ?? false))
        }
        let confirmation = values["needsconfirmation"]?.lowercased()
        return .success(ScriptCommand(
            file: file,
            title: title,
            packageName: values["packagename"].flatMap { $0.isEmpty ? nil : $0 },
            mode: mode,
            needsConfirmation: confirmation == "true" || confirmation == "1" || confirmation == "yes",
            icon: values["icon"].flatMap { $0.isEmpty ? nil : $0 },
            arguments: arguments
        ))
    }

    /// Every runnable command in a folder, with the files that failed to parse alongside.
    static func scan(in folder: URL, fileManager: FileManager = .default) -> ScriptScan {
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        var commands: [ScriptCommand] = []
        var failures: [ScriptFailure] = []
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            switch parse(file: entry) {
            case let .success(command):
                commands.append(command)
            case let .failure(error):
                failures.append(ScriptFailure(file: entry.lastPathComponent, error: error))
            }
        }
        commands.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        failures.sort { $0.file < $1.file }
        return ScriptScan(commands: commands, failures: failures)
    }

    static func scan(fileManager: FileManager = .default) -> ScriptScan {
        Paths.prepareSupportFolders()
        return scan(in: Paths.scripts, fileManager: fileManager)
    }

    /// The arguments typed after the title in the launcher's query, when the query starts with
    /// this command's title followed by a space.
    func argumentsText(in query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > title.count else { return nil }
        guard trimmed.lowercased().hasPrefix(title.lowercased()) else { return nil }
        let after = trimmed.dropFirst(title.count)
        guard after.first?.isWhitespace == true else { return nil }
        return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A file that failed to parse, with its typed failure.
nonisolated struct ScriptFailure: Identifiable, Sendable, Equatable {
    let file: String
    let error: ScriptParseError
    var id: String {
        file
    }
}

/// What a scan of the Scripts folder found.
nonisolated struct ScriptScan: Sendable {
    var commands: [ScriptCommand] = []
    var failures: [ScriptFailure] = []
}

/// Runs script commands: a 60 second timeout, argv from the text typed after the title.
nonisolated enum ScriptRunner {
    static let timeout: TimeInterval = 60

    static func run(_ script: ScriptCommand, arguments: [String]) async throws -> ShellResult {
        try await Shell.run(script.file, arguments, in: script.file.deletingLastPathComponent(), timeout: timeout)
    }

    /// Splits typed arguments on whitespace, keeping "quoted spans" together.
    static func splitArguments(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var inWord = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                inWord = true
            } else if character == "\\", quote != nil {
                escaped = true
            } else if let open = quote, character == open {
                quote = nil
                inWord = true
            } else if quote == nil, character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if quote == nil, character.isWhitespace {
                if inWord {
                    result.append(current)
                    current = ""
                    inWord = false
                }
            } else {
                current.append(character)
                inWord = true
            }
        }
        if inWord || quote != nil {
            result.append(current)
        }
        return result
    }

    /// The last non-empty line, for failure HUDs and compact output.
    static func lastLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.last
    }

    static func template(title: String = "My Script") -> String {
        """
        #!/bin/bash

        # @raycast.schemaVersion 1
        # @raycast.title \(title)
        # @raycast.mode fullOutput
        # @raycast.packageName Scripts
        # @raycast.icon 🤖

        echo "Hello from \(title)!"
        """
    }
}

/// A small window showing a fullOutput script's stdout. One reused panel, like the HUD.
@MainActor
enum ScriptOutputWindow {
    private static var panel: NSPanel?

    static func show(title: String, output: String) {
        let panel = panel ?? makePanel()
        Self.panel = panel
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView()
        text.string = output.isEmpty ? String(localized: "(no output)", bundle: .floe, comment: "Shown in place of what a script printed when it printed nothing.") : output
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        scroll.documentView = text
        panel.contentView = scroll
        panel.title = title
        panel.makeKeyAndOrderFront(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        return panel
    }
}
