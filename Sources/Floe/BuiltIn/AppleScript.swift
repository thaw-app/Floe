//
//  AppleScript.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Subprocess

/// How a script ended.
nonisolated enum AppleScriptOutcome: Equatable, Sendable {
    case text(String)
    /// macOS did not let Floe control the app (error -1743).
    case refused
    case failed
}

/// Runs a script and answers when it ends. Tests pass their own, so no test ever talks to a browser.
typealias AppleScriptRunner = @Sendable (String) async -> AppleScriptOutcome

/// The one place a script is handed to macOS. Each caller reads the answer its own way and words its own messages.
nonisolated enum AppleScript {
    /// What macOS reports when the user has not allowed Floe to control the app.
    static let refusedErrorNumber = -1743

    /// Everything a run reported, as plain values that may cross threads.
    struct Execution: Equatable, Sendable {
        /// False when the source could not be made into a script at all.
        var didRun = true
        /// What the script returned, when that reads as text.
        var text: String?
        /// Whether macOS reported an error, with or without a number.
        var hasError = false
        var errorNumber: Int?
        var errorMessage: String?

        var isRefused: Bool {
            errorNumber == AppleScript.refusedErrorNumber
        }

        init(didRun: Bool = true, text: String? = nil, hasError: Bool = false, errorNumber: Int? = nil, errorMessage: String? = nil) {
            self.didRun = didRun
            self.text = text
            self.hasError = hasError
            self.errorNumber = errorNumber
            self.errorMessage = errorMessage
        }

        /// What `osascript` left behind: the answer and a line break, or `12:34: execution error: Why. (-1743)`.
        init(status: Int32, output: String, errors: String) {
            guard status != 0 else {
                self.init(text: output.hasSuffix("\n") ? String(output.dropLast()) : output)
                return
            }
            let report = errors.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = report.firstMatch(of: /error: (?<message>.*) \((?<number>-?\d+)\)$/.dotMatchesNewlines())
            self.init(
                didRun: false,
                hasError: true,
                errorNumber: parts.flatMap { Int($0.number) },
                errorMessage: parts.map { String($0.message) } ?? (report.isEmpty ? nil : report)
            )
        }
    }

    /// The script runs in `osascript`, because compiling one in this process makes macOS keep its 13 MB
    /// of malware rules here for good.
    static func execute(_ source: String) async -> Execution {
        let result = try? await Subprocess.run(
            .path("/usr/bin/osascript"),
            input: .string(source),
            output: .string(limit: 16 * 1024 * 1024),
            error: .string(limit: 64 * 1024)
        )
        guard let result, case let .exited(status) = result.terminationStatus else { return Execution(didRun: false, hasError: true) }
        return Execution(status: status, output: result.standardOutput, errors: result.standardError)
    }

    /// Runs the script and reports back on the main thread, for a caller that does not wait.
    static func execute(_ source: String, priority: TaskPriority, completion: @escaping @MainActor (Execution) -> Void) {
        let lease = PanelWork.begin()
        Task(priority: priority) {
            defer {
                withExtendedLifetime(lease) {
                    // Keep idle exit blocked through both script execution and its completion callback.
                }
            }
            await completion(execute(source))
        }
    }

    static let run: AppleScriptRunner = { source in
        let execution = await execute(source)
        if let number = execution.errorNumber {
            return number == refusedErrorNumber ? .refused : .failed
        }
        guard execution.didRun else { return .failed }
        return .text(execution.text ?? "")
    }

    static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
