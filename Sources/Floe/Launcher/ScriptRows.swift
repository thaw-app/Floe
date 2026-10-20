//
//  ScriptRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The user's script commands, as the launcher runs them and shows what they printed.
final class ScriptRows {
    var host = RowHost()
    /// What is typed in the search field, which holds a script's arguments after its title.
    var typed: () -> String = { "" }
    /// Counts a run as a use of the script, for the ranking.
    var recordUse: (String) -> Void = { _ in
        // Set by LauncherFeatures.
    }
    /// Asks before a script that declares it needs confirming runs.
    var confirms: (ScriptCommand) -> Bool = { ScriptRows.confirmRun(of: $0) }
    var runScript: @Sendable (ScriptCommand, [String]) async throws -> ShellResult = { try await ScriptRunner.run($0, arguments: $1) }
    var showOutput: (_ title: String, _ output: String) -> Void = { ScriptOutputWindow.show(title: $0, output: $1) }

    /// Runs a script with the given argv. Output follows its mode: a window for fullOutput, a HUD for compact
    /// and inline, nothing for silent. Failures show a HUD with the last stderr line.
    func run(_ script: ScriptCommand, argumentStrings: [String] = []) {
        guard !script.needsConfirmation || confirms(script) else { return }
        recordUse(RootItem.script(script).id)
        host.leave()
        Task { [weak self, runScript] in
            let result: ShellResult
            do {
                result = try await runScript(script, argumentStrings)
            } catch {
                await MainActor.run { [weak self] in
                    self?.host.showHUD(String(localized: "\(script.title) failed: \(error.localizedDescription)", bundle: .floe, comment: "The first placeholder is the name of a script, the second is the reason."))
                }
                return
            }
            await MainActor.run { [weak self] in self?.show(result, of: script) }
        }
    }

    private func show(_ result: ShellResult, of script: ScriptCommand) {
        guard result.succeeded else {
            let line = ScriptRunner.lastLine(result.errorOutput) ?? ScriptRunner.lastLine(result.output)
                ?? String(localized: "exit code \(result.status)", bundle: .floe, comment: "The reason a script failed, when it printed nothing. The placeholder is a number.")
            host.showHUD(String(localized: "\(script.title) failed: \(line)", bundle: .floe, comment: "The first placeholder is the name of a script, the second is the reason."))
            return
        }
        switch script.mode {
        case .silent:
            break
        case .inline, .compact:
            host.showHUD(ScriptRunner.lastLine(result.output) ?? String(localized: "Done (script finished)", defaultValue: "Done", bundle: .floe, comment: "Shown briefly when a script finished and printed nothing."))
        case .fullOutput:
            showOutput(script.title, result.trimmedOutput)
        }
    }

    private static func confirmRun(of script: ScriptCommand) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Run \(script.title)?", bundle: .floe, comment: "The placeholder is the name of a script.")
        alert.informativeText = script.displayPackage
        alert.addButton(withTitle: String(localized: "Run", bundle: .floe, comment: "A verb on a button: run the shortcut or script."))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .floe))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension ScriptRows: RowOwner {
    func returnTitle(for _: RootItem) -> String? {
        nil
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .script(script) = item else { return false }
        run(script, argumentStrings: ScriptRunner.splitArguments(script.argumentsText(in: typed()) ?? ""))
        return true
    }
}
