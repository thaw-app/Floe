//
//  PiTextStream.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/Providers/PiCLI.swift, and modified: what is kept is
//  how a throwaway pi is started (no session, extensions, skills, prompt templates, themes or
//  context files, and no version check). Droppy Code starts it that way to list models over RPC;
//  Floe starts it with no tools for one prompt and one answer, and reads pi's JSON event lines.

import Foundation

/// One prompt, streamed back from the `pi` command line tool with no tools and no project.
nonisolated enum PiTextStream {
    typealias Event = ToolTextStream.Event

    /// One prompt from standard input, answered as JSON lines. `--no-approve` ignores a project's own files.
    static func arguments(model: String?) -> [String] {
        [
            "-p", "--mode", "json", "--no-session", "--no-tools", "--no-extensions", "--no-skills",
            "--no-prompt-templates", "--no-themes", "--no-context-files", "--no-approve",
            "--system-prompt", TextGeneration.instructions,
        ] + (model.map { ["--model", $0] } ?? [])
    }

    /// The tool's environment for the run, on top of the login shell's.
    static func environment(_ base: [String: String]) -> [String: String] {
        var environment = base
        environment["PI_SKIP_VERSION_CHECK"] = "1"
        return environment
    }

    /// Nil for a line that carries nothing to show: the session, a turn, the prompt echoed back, thinking, a retry.
    static func event(in line: String) -> Event? {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return nil }
        switch message["type"] as? String {
        case "message_update":
            guard let update = message["assistantMessageEvent"] as? [String: Any], update["type"] as? String == "text_delta",
                  let text = update["delta"] as? String, !text.isEmpty
            else { return nil }
            return .text(text)
        case "message_end":
            guard let reply = message["message"] as? [String: Any], reply["role"] as? String == "assistant" else { return nil }
            if let reason = reply["stopReason"] as? String, ["error", "aborted"].contains(reason) {
                let text = reply["errorMessage"] as? String
                return .failure(text.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "pi stopped before finishing.", bundle: .floe, comment: "The word pi is the name of a command and stays as written."))
            }
            // The finished message is the authoritative text; pi may have tried more than once to get it.
            let blocks = reply["content"] as? [[String: Any]] ?? []
            return .result(blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined())
        case "tool_execution_start":
            return .stop(String(localized: "pi tried to use a tool, which Floe does not allow, so it was stopped. Choose another tool under Settings › AI.", bundle: .floe, comment: "The word pi is the name of a command and stays as written."))
        default:
            return nil
        }
    }
}
