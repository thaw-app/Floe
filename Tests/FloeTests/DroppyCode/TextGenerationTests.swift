//
//  TextGenerationTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Shell scripts stand in for the claude and codex tools, so no model is called.
struct TextGenerationTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-textgen-\(UUID().uuidString)")
    private let environment = ["PATH": "/usr/bin:/bin"]

    private func script(_ body: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("tool-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func claudeRunsWithoutToolsOnTheModelAsked() {
        let output = URL(fileURLWithPath: "/tmp/out.txt")
        let fast = TextGeneration.arguments(for: .claude(executable: output, model: nil), output: output)
        #expect(Array(fast.prefix(7)) == ["-p", "--output-format", "text", "--model", "haiku", "--tools", ""])
        #expect(fast.contains("--no-session-persistence"))
        let asked = TextGeneration.arguments(for: .claude(executable: output, model: "sonnet"), output: output)
        #expect(asked[4] == "sonnet")
    }

    @Test func codexRunsReadOnlyAndWritesItsAnswerToAFile() {
        let output = URL(fileURLWithPath: "/tmp/out.txt")
        let configured = TextGeneration.arguments(for: .codex(executable: output, model: nil), output: output)
        #expect(Array(configured.prefix(5)) == ["exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only"])
        #expect(!configured.contains("--model"))
        #expect(Array(configured.suffix(3)) == ["--output-last-message", "/tmp/out.txt", "-"])
        let asked = TextGeneration.arguments(for: .codex(executable: output, model: "gpt-5"), output: output)
        #expect(asked.contains("--model"))
        #expect(asked.contains("gpt-5"))
    }

    @Test func codexRunsWithoutItsCommands() {
        let output = URL(fileURLWithPath: "/tmp/out.txt")
        let arguments = TextGeneration.arguments(for: .codex(executable: output, model: nil), output: output)
        let settings = zip(arguments, arguments.dropFirst()).filter { $0.0 == "--config" }.map(\.1)
        #expect(settings.contains("features.shell_tool=false"))
        #expect(settings.contains("features.unified_exec=false"))
        #expect(settings.contains("features.plugins=false"))
        let withServers = TextGeneration.arguments(for: .codex(executable: output, model: nil), output: output, mcpServers: ["GitKraken", "node_repl"])
        let serverSettings = zip(withServers, withServers.dropFirst()).filter { $0.0 == "--config" }.map(\.1)
        #expect(serverSettings.contains("mcp_servers.GitKraken.enabled=false"))
        #expect(serverSettings.contains("mcp_servers.node_repl.enabled=false"))
    }

    @Test func aCodexTooOldToKeepServersOffIsRefused() async throws {
        #expect(TextGeneration.codexKeepsServersOff(version: "codex-cli 0.157.1"))
        #expect(TextGeneration.codexKeepsServersOff(version: "codex-cli 0.160.0"))
        #expect(TextGeneration.codexKeepsServersOff(version: "codex-cli 1.0.0"))
        #expect(!TextGeneration.codexKeepsServersOff(version: "codex-cli 0.149.1"))
        #expect(!TextGeneration.codexKeepsServersOff(version: "codex-cli 0.157.0"))
        #expect(!TextGeneration.codexKeepsServersOff(version: "codex-cli 0.157.1-alpha"))
        #expect(!TextGeneration.codexKeepsServersOff(version: ""))

        let old = try TextGeneration.Engine.codex(executable: script("[ \"$1\" = --version ] && { echo 'codex-cli 0.149.1'; exit 0; }\necho '[]'"), model: nil)
        await #expect(throws: ShellError.self) {
            try await TextGeneration.run("why?", engine: old, environment: environment)
        }
    }

    @Test func codexsServersAreReadOrTheRunIsRefused() async throws {
        #expect(TextGeneration.codexServers(in: Data(#"[{"name":"GitKraken"},{"name":"computer-use"}]"#.utf8)) == ["GitKraken", "computer-use"])
        #expect(TextGeneration.codexServers(in: Data("[]".utf8)) == [])
        #expect(TextGeneration.codexServers(in: Data(#"[{"name":"a.b"}]"#.utf8)) == nil, "a name --config would read as a path")
        #expect(TextGeneration.codexServers(in: Data("not json".utf8)) == nil)

        // A Codex that cannot list its servers gives no answer rather than one with its tools on.
        let engine = try TextGeneration.Engine.codex(executable: script("[ \"$1\" = --version ] && { echo 'codex-cli 0.157.1'; exit 0; }\n[ \"$1\" = mcp ] && exit 1; echo ran > /dev/null"), model: nil)
        await #expect(throws: ShellError.self) {
            try await TextGeneration.run("why?", engine: engine, environment: environment)
        }
    }

    @Test func codexRunsInAnEmptyFolderOfItsOwn() async throws {
        let body = "[ \"$1\" = --version ] && { echo 'codex-cli 0.157.1'; exit 0; }\n[ \"$1\" = mcp ] && { echo '[]'; exit 0; }\nwhile [ $# -gt 0 ]; do [ \"$1\" = --output-last-message ] && out=\"$2\"; shift; done\n: > \"$out\"; n=$(ls -A | wc -l | tr -d ' '); { echo \"$n\"; pwd; } > \"$out\""
        let engine = try TextGeneration.Engine.codex(executable: script(body), model: nil)
        let lines = try await TextGeneration.run("why?", engine: engine, environment: environment).split(separator: "\n").map(String.init)
        // The answer file is the one thing in the folder, and the folder is gone once the run is over.
        #expect(lines.first == "1")
        #expect(lines.last?.contains("floe-answer-") == true)
        #expect(lines.last.map { FileManager.default.fileExists(atPath: $0) } == false)
    }

    @Test func claudesAnswerIsWhatItPrints() async throws {
        let engine = try TextGeneration.Engine.claude(executable: script("printf 'answer to: '; cat; echo"), model: nil)
        #expect(try await TextGeneration.run("why?", engine: engine, environment: environment) == "answer to: why?")
    }

    @Test func codexsAnswerIsTheFileItWrites() async throws {
        // The file is the argument after --output-last-message; standard output is the session's noise.
        let body = "[ \"$1\" = --version ] && { echo 'codex-cli 0.157.1'; exit 0; }\n[ \"$1\" = mcp ] && { echo '[]'; exit 0; }\nwhile [ $# -gt 0 ]; do [ \"$1\" = --output-last-message ] && out=\"$2\"; shift; done\necho noise; printf '  from codex\\n' > \"$out\""
        let engine = try TextGeneration.Engine.codex(executable: script(body), model: nil)
        #expect(try await TextGeneration.run("why?", engine: engine, environment: environment) == "from codex")
    }

    @Test func aFailingToolThrowsWhatItSaid() async throws {
        let engine = try TextGeneration.Engine.claude(executable: script("echo 'not signed in' >&2; exit 1"), model: nil)
        let error = await #expect(throws: ShellError.self) {
            try await TextGeneration.run("why?", engine: engine, environment: environment)
        }
        #expect(error?.message == "not signed in")
    }

    @Test func anEmptyAnswerIsAnError() async throws {
        let engine = try TextGeneration.Engine.claude(executable: script("cat > /dev/null"), model: nil)
        let error = await #expect(throws: ShellError.self) {
            try await TextGeneration.run("why?", engine: engine, environment: environment)
        }
        #expect(error?.message == "The model gave no answer.")
    }

    @Test func eachEngineHasItsOwnDeadline() {
        let tool = URL(fileURLWithPath: "/bin/sh")
        #expect(TextGeneration.Engine.claude(executable: tool, model: nil).timeout == 120)
        #expect(TextGeneration.Engine.codex(executable: tool, model: nil).timeout == 180)
        #expect(TextGeneration.Engine.codex(executable: tool, model: nil).executable == tool)
        #expect(TextGeneration.Engine.opencode(executable: tool, model: nil).timeout == 180)
        #expect(TextGeneration.Engine.pi(executable: tool, model: nil).timeout == 180)
        #expect(TextGeneration.Engine.pi(executable: tool, model: "a/b").executable == tool)
    }
}
