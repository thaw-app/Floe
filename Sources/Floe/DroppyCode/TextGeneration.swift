//
//  TextGeneration.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/Providers/TextGeneration.swift, and modified: the
//  thread title and commit message prompts are left out, the prompt is the caller's, every engine
//  takes an optional model, a failure is thrown with the tool's own words, the arguments are
//  built by a function a test can call, claude's answer can be streamed (ClaudeTextStream.swift),
//  and opencode and pi are engines too (OpencodeTextStream.swift, PiTextStream.swift).

import Foundation

/// One-shot text generation through a provider's command line tool with no tools of its own,
/// on the account the user is already signed in to.
nonisolated enum TextGeneration {
    enum Engine: Sendable, Equatable {
        case claude(executable: URL, model: String?)
        case codex(executable: URL, model: String?)
        /// The model is "provider/model", as opencode's `--model` takes it; nil is its own default.
        case opencode(executable: URL, model: String?)
        /// The model is what pi's `--model` takes, such as "provider/model"; nil is its own default.
        case pi(executable: URL, model: String?)

        var executable: URL {
            switch self {
            case let .claude(executable, _), let .codex(executable, _), let .opencode(executable, _), let .pi(executable, _): executable
            }
        }

        var timeout: TimeInterval {
            switch self {
            case .claude: 120
            case .codex, .opencode, .pi: 180
            }
        }
    }

    /// What opencode and pi are told in place of their coding prompts, which run to thousands of words.
    static let instructions = "Answer the question directly. You have no tools."

    /// The arguments for one run. Codex writes its last message to `output`, since its standard
    /// output carries the whole session. For opencode, `output` is the empty folder it runs in.
    static func arguments(for engine: Engine, output: URL, mcpServers: [String] = []) -> [String] {
        switch engine {
        case let .claude(_, model):
            [
                "-p", "--output-format", "text", "--model", model ?? "haiku", "--tools", "",
                "--disable-slash-commands", "--strict-mcp-config", "--permission-mode", "dontAsk",
                "--no-session-persistence",
            ]
        case let .codex(_, model):
            ["exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only"]
                + (model.map { ["--model", $0] } ?? [])
                + ["--config", "model_reasoning_effort=\"low\""] + codexToolsOff
                + mcpServers.flatMap { ["--config", "mcp_servers.\($0).enabled=false"] }
                + ["--output-last-message", output.path, "-"]
        case let .opencode(_, model):
            OpencodeTextStream.arguments(model: model, directory: output)
        case let .pi(_, model):
            PiTextStream.arguments(model: model)
        }
    }

    /// Codex has no switch for no tools: these turn off its commands, its plugins and what drives the Mac.
    /// The user's own MCP servers are turned off by name, from `codexServers(in:)`.
    static let codexToolsOff = [
        "features.shell_tool=false", "features.unified_exec=false", "features.plugins=false",
        "features.apps=false", "features.browser_use=false", "features.computer_use=false",
    ].flatMap { ["--config", $0] }

    /// The MCP servers in `codex mcp list --json`, or nil when a name cannot be written as a bare key in `--config`:
    /// a server Floe cannot turn off would stay on for the answer.
    static func codexServers(in listing: Data) -> [String]? {
        guard let servers = try? JSONSerialization.jsonObject(with: listing) as? [[String: Any]] else { return nil }
        let names = servers.compactMap { $0["name"] as? String }
        let bare = names.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } }
        return names.count == servers.count && bare ? names : nil
    }

    /// The oldest Codex seen to keep a server turned off in `codex exec`, checked with a server that marks its start.
    /// An older one may list a server as off and start it anyway.
    static let codexKeepsServersOff = [0, 157, 1]

    /// Whether `codex --version`, as "codex-cli 0.157.1", is at least `codexKeepsServersOff`. False for what does not read.
    static func codexKeepsServersOff(version: String) -> Bool {
        guard let number = version.split(separator: " ").last else { return false }
        let parts = number.split(separator: ".").map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return false }
        return parts.compactMap(\.self).lexicographicallyPrecedes(codexKeepsServersOff) == false
    }

    /// The MCP servers this Codex would start, read from it before the answer so each can be turned off.
    /// Throws when they cannot be read, or when this Codex is too old to keep them off, rather than answer with them on.
    private static func codexServers(of executable: URL, in directory: URL, environment: [String: String]) async throws -> [String] {
        let version = try await Shell.run(executable, ["--version"], in: directory, environment: environment, timeout: 30)
        guard version.succeeded, codexKeepsServersOff(version: version.trimmedOutput) else {
            throw ShellError(String(localized: "Codex can't answer: update it to 0.157.1 or later, which keeps its MCP servers off.", bundle: .floe))
        }
        let listing = try await Shell.run(executable, ["mcp", "list", "--json"] + codexToolsOff, in: directory, environment: environment, timeout: 30)
        guard listing.succeeded, let names = codexServers(in: Data(listing.trimmedOutput.utf8)) else {
            throw ShellError(String(localized: "Codex can't answer: Floe couldn't turn off its MCP servers.", bundle: .floe))
        }
        return names
    }

    /// Answers a prompt, with text handed to `onText` as it arrives. Claude and pi stream. Codex's one-shot run
    /// prints its session, not its answer, and opencode prints its text once it is complete, so theirs come whole.
    @concurrent
    static func run(
        _ prompt: String,
        engine: Engine,
        environment: [String: String] = LoginEnvironment.current,
        onText: @Sendable (String) async -> Void
    ) async throws -> String {
        switch engine {
        case let .claude(executable, model):
            return try await ClaudeTextStream.run(prompt, executable: executable, model: model, environment: environment, onText: onText)
        case .codex:
            return try await run(prompt, engine: engine, environment: environment)
        case .opencode, .pi:
            return try await inAnswerFolder { folder in
                let launch = launch(engine, in: folder, environment: environment)
                let read = if case .pi = engine {
                    PiTextStream.event(in:)
                } else {
                    OpencodeTextStream.event(in:)
                }
                return try await ToolTextStream.run(prompt, launch: launch, read: read, onText: onText)
            }
        }
    }

    /// Runs `work` in an empty folder of its own: there is no project for the tool to read, and nothing is left behind.
    private static func inAnswerFolder<T>(_ work: (URL) async throws -> T) async throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-answer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await work(folder)
    }

    /// How opencode or pi is started in `folder`. Claude and codex have runs of their own.
    static func launch(_ engine: Engine, in folder: URL, environment: [String: String]) -> ToolTextStream.Launch {
        let environment: [String: String] = switch engine {
        case .opencode: OpencodeTextStream.environment(environment)
        case .pi: PiTextStream.environment(environment)
        case .claude, .codex: environment
        }
        return ToolTextStream.Launch(
            executable: engine.executable,
            arguments: arguments(for: engine, output: folder),
            directory: folder,
            environment: environment,
            timeout: engine.timeout
        )
    }

    /// The answer whole, with nothing handed on before it. For claude and codex, which print it or write it to a file.
    @concurrent
    static func run(_ prompt: String, engine: Engine, environment: [String: String] = LoginEnvironment.current) async throws -> String {
        switch engine {
        case .opencode, .pi:
            return try await run(prompt, engine: engine, environment: environment) { _ in
                // Only the whole answer is wanted.
            }
        case .claude, .codex:
            break
        }
        return try await inAnswerFolder { directory in
            let output = directory.appendingPathComponent("answer.txt")
            let servers = if case .codex = engine {
                try await codexServers(of: engine.executable, in: directory, environment: environment)
            } else {
                [String]()
            }
            let result = try await Shell.run(
                engine.executable,
                arguments(for: engine, output: output, mcpServers: servers),
                in: directory,
                environment: environment,
                input: Data(prompt.utf8),
                timeout: engine.timeout
            )
            guard result.succeeded else {
                throw ShellError(result.failureMessage)
            }
            let text: String = if case .codex = engine {
                ((try? String(contentsOf: output, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                result.trimmedOutput
            }
            guard !text.isEmpty else {
                throw ShellError(String(localized: "The model gave no answer.", bundle: .floe))
            }
            return text
        }
    }
}
