//
//  OpencodeTextStream.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/MCP/MCPSessionOverrides.swift, and modified: what is
//  kept is handing opencode its configuration through OPENCODE_CONFIG_CONTENT. Droppy Code passes
//  MCP servers that way for a whole agent session over ACP; Floe passes an agent that may use no
//  tool, for one prompt and one answer from `opencode run`, and reads that command's JSON lines.

import Foundation

/// One prompt, answered by the `opencode` command line tool with no tools and no project.
nonisolated enum OpencodeTextStream {
    typealias Event = ToolTextStream.Event

    /// The agent Floe defines for the run. opencode's own default agent may edit files and run commands.
    static let agent = "floe-answer"

    /// One message from standard input, as JSON lines. The folder is an empty one, so there is no project to read.
    static func arguments(model: String?, directory: URL) -> [String] {
        ["run", "--pure", "--agent", agent, "--format", "json", "--title", "Floe", "--dir", directory.path]
            + (model.map { ["--model", $0] } ?? [])
    }

    /// The agent, as opencode's configuration: a short prompt in place of its coding one, and every permission denied.
    static var configuration: String {
        let agent: [String: Any] = [
            "mode": "primary",
            "description": "Answers one question for Floe, with no tools",
            "prompt": TextGeneration.instructions,
            "permission": ["*": "deny"],
        ]
        let root: [String: Any] = ["$schema": "https://opencode.ai/config.json", "agent": [Self.agent: agent]]
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }

    /// The tool's environment for the run, on top of the login shell's.
    static func environment(_ base: [String: String]) -> [String: String] {
        var environment = base
        environment["OPENCODE_CONFIG_CONTENT"] = configuration
        // Denied for every agent too: opencode falls back to its default agent when it cannot find the one named.
        environment["OPENCODE_PERMISSION"] = #"{"*":"deny"}"#
        // opencode run has no option to leave a session unsaved; a database in memory is gone when it exits.
        environment["OPENCODE_DB"] = ":memory:"
        // Without these it loads the instructions and skills written for Claude Code and for other agents.
        environment["OPENCODE_DISABLE_CLAUDE_CODE"] = "1"
        environment["OPENCODE_DISABLE_EXTERNAL_SKILLS"] = "1"
        environment["OPENCODE_DISABLE_AUTOUPDATE"] = "1"
        return environment
    }

    /// Nil for a line that carries nothing to show: a step's start or finish, or anything that is not JSON.
    static func event(in line: String) -> Event? {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return nil }
        let part = message["part"] as? [String: Any]
        if part?["type"] as? String == "tool" {
            return .stop(String(localized: "opencode tried to use a tool, which Floe does not allow, so it was stopped. Choose another tool under Settings › AI.", bundle: .floe, comment: "The word opencode is the name of a command and stays as written."))
        }
        switch message["type"] as? String {
        case "text":
            // opencode prints a text part once it is complete, so an answer arrives in one piece.
            guard let text = part?["text"] as? String, !text.isEmpty else { return nil }
            return .text(text)
        case "error":
            let error = message["error"] as? [String: Any]
            let text = (error?["data"] as? [String: Any])?["message"] as? String ?? error?["name"] as? String
            return .failure(text.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "opencode stopped before finishing.", bundle: .floe, comment: "The word opencode is the name of a command and stays as written."))
        default:
            return nil
        }
    }
}
