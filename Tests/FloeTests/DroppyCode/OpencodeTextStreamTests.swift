//
//  OpencodeTextStreamTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The named lines are what `opencode run --format json` printed on a Mac with opencode 1.18.34.
/// The reasoning and tool lines are written by hand, from the part types in opencode's own source.
struct OpencodeTextStreamTests {
    private static nonisolated let stepStart = #"{"type":"step_start","timestamp":1791159870759,"sessionID":"ses_ef68d63a2ffe07CTQ1Eyelrlap","part":{"id":"prt_10972a50c001ttJev75CFQvkdF","messageID":"msg_109729f33001Zdl7HmG0BmMIG4","sessionID":"ses_ef68d63a2ffe07CTQ1Eyelrlap","type":"step-start"}}"#
    private static nonisolated let text = #"{"type":"text","timestamp":1791159870759,"sessionID":"ses_ef68d63a2ffe07CTQ1Eyelrlap","part":{"id":"prt_10972a511001cYh0lV2SKkRsPl","messageID":"msg_109729f33001Zdl7HmG0BmMIG4","sessionID":"ses_ef68d63a2ffe07CTQ1Eyelrlap","type":"text","text":"ok","time":{"start":1791159870738,"end":1791159870745}}}"#
    private static nonisolated let stepFinish = #"{"type":"step_finish","timestamp":1791159870759,"sessionID":"ses_ef68d63a2ffe07CTQ1Eyelrlap","part":{"id":"prt_10972a51e001megXYX3UwTfrL6","reason":"stop","messageID":"msg_109729f33001Zdl7HmG0BmMIG4","sessionID":"ses_ef68d63a2ffe07CTQ1Eyelrlap","type":"step-finish","tokens":{"total":174,"input":172,"output":2,"reasoning":0,"cache":{"write":0,"read":0}},"cost":0.000027}}"#
    /// What it printed, with exit code 1, for a model it does not have.
    private static nonisolated let error = #"{"type":"error","timestamp":1791159887409,"sessionID":"ses_ef68d1c82ffe2ls43mWIJd4eMU","error":{"name":"UnknownError","data":{"message":"Unexpected server error. Check server logs for details.","ref":"err_74e3399e"}}}"#
    /// On standard error, when the agent named is not in its configuration.
    private static nonisolated let fallbackWarning = "\u{1B}[93m\u{1B}[1m! \u{1B}[0m agent \"floe-answer\" not found. Falling back to default agent"

    private let tool = URL(fileURLWithPath: "/opt/homebrew/bin/opencode")
    private let folder = URL(fileURLWithPath: "/tmp/floe-answer-1")

    // MARK: Arguments and environment

    @Test func itRunsOneMessageAsFloesAgentInTheFolderGiven() {
        let arguments = TextGeneration.arguments(for: .opencode(executable: tool, model: nil), output: folder)
        #expect(arguments == ["run", "--pure", "--agent", "floe-answer", "--format", "json", "--title", "Floe", "--dir", "/tmp/floe-answer-1"])
        #expect(!arguments.contains("--model"), "with no model typed, opencode's own default stands")
    }

    @Test func theModelIsPassedAsWritten() {
        let arguments = TextGeneration.arguments(for: .opencode(executable: tool, model: "anthropic/claude-sonnet-4-5"), output: folder)
        #expect(Array(arguments.suffix(2)) == ["--model", "anthropic/claude-sonnet-4-5"])
    }

    @Test func nothingApprovesPermissionsOrContinuesASession() {
        let arguments = TextGeneration.arguments(for: .opencode(executable: tool, model: "a/b"), output: folder)
        for flag in ["--auto", "-c", "--continue", "-s", "--session", "--fork", "--share", "-i", "--interactive", "-f", "--file"] {
            #expect(!arguments.contains(flag))
        }
    }

    @Test func theAgentMayUseNoToolAndCarriesAShortPrompt() throws {
        let data = Data(OpencodeTextStream.configuration.utf8)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let agents = try #require(root["agent"] as? [String: Any])
        #expect(Array(agents.keys) == [OpencodeTextStream.agent])
        let agent = try #require(agents[OpencodeTextStream.agent] as? [String: Any])
        #expect(agent["mode"] as? String == "primary", "a subagent is not run by name: opencode would fall back to its default agent")
        #expect(agent["permission"] as? [String: String] == ["*": "deny"])
        #expect(agent["prompt"] as? String == TextGeneration.instructions)
        #expect(TextGeneration.instructions.count < 100)
    }

    @Test func theEnvironmentDeniesToolsForEveryAgentAndKeepsNoSession() {
        let launch = TextGeneration.launch(.opencode(executable: tool, model: nil), in: folder, environment: ["PATH": "/usr/bin", "OPENCODE_PERMISSION": #"{"*":"allow"}"#])
        #expect(launch.environment["PATH"] == "/usr/bin", "the login shell's environment is kept, for the tool's own keys")
        #expect(launch.environment["OPENCODE_CONFIG_CONTENT"] == OpencodeTextStream.configuration)
        #expect(launch.environment["OPENCODE_PERMISSION"] == #"{"*":"deny"}"#, "whatever the shell had set")
        #expect(launch.environment["OPENCODE_DB"] == ":memory:")
        #expect(launch.environment["OPENCODE_DISABLE_CLAUDE_CODE"] == "1")
        #expect(launch.environment["OPENCODE_DISABLE_EXTERNAL_SKILLS"] == "1")
        #expect(launch.directory == folder)
        #expect(launch.arguments.contains(folder.path))
        #expect(launch.timeout == 180)
    }

    // MARK: Lines

    @Test func aTextPartIsText() {
        #expect(OpencodeTextStream.event(in: Self.text) == .text("ok"))
    }

    @Test(arguments: [
        stepStart,
        stepFinish,
        fallbackWarning,
        #"{"type":"text","part":{"type":"text","text":""}}"#,
        #"{"type":"text","part":"not a part"}"#,
        #"{"type":"reasoning","part":{"type":"reasoning","text":"hm"}}"#,
        #"["type","text"]"#,
        "ok",
        "",
    ])
    func aLineWithNothingToShowIsSkipped(line: String) {
        #expect(OpencodeTextStream.event(in: line) == nil)
    }

    @Test func anErrorLineIsTheToolsOwnMessage() {
        #expect(OpencodeTextStream.event(in: Self.error) == .failure("Unexpected server error. Check server logs for details."))
        #expect(OpencodeTextStream.event(in: #"{"type":"error","error":{"name":"ProviderAuthError"}}"#) == .failure("ProviderAuthError"))
        #expect(OpencodeTextStream.event(in: #"{"type":"error"}"#) == .failure("opencode stopped before finishing."))
    }

    @Test func aToolPartStopsTheRun() {
        let line = #"{"type":"tool_use","part":{"type":"tool","tool":"bash","state":{"status":"completed"}}}"#
        guard case let .stop(message) = OpencodeTextStream.event(in: line) else {
            Issue.record("a tool part should stop the run")
            return
        }
        #expect(message.contains("opencode tried to use a tool"))
        #expect(message.contains("Settings › AI"))
    }

    // MARK: A run, against a script that prints what the tool printed

    private func script(_ body: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-fake-opencode-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\ncat > /dev/null\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    @Test func theAnswerIsTheTextPartAmongTheStepLines() async throws {
        let tool = try script("printf '%s\\n' '\(Self.stepStart)' '\(Self.text)' '\(Self.stepFinish)'")
        defer { try? FileManager.default.removeItem(at: tool) }
        let answer = try await TextGeneration.run("Reply with exactly: ok", engine: .opencode(executable: tool, model: nil), environment: ["PATH": "/usr/bin:/bin"]) { _ in }
        #expect(answer == "ok")
        #expect(try await TextGeneration.run("Reply with exactly: ok", engine: .opencode(executable: tool, model: nil), environment: ["PATH": "/usr/bin:/bin"]) == "ok")
    }

    @Test func itRunsInAnEmptyFolderThatIsGoneAfterwards() async throws {
        // The script answers with the folder it was started in and how many entries it holds.
        let tool = try script(#"printf '{"type":"text","part":{"type":"text","text":"%s %s"}}\n' "$(pwd -P)" "$(ls -A | wc -l | tr -d ' ')""#)
        defer { try? FileManager.default.removeItem(at: tool) }
        let answer = try await TextGeneration.run("hi", engine: .opencode(executable: tool, model: nil), environment: ["PATH": "/usr/bin:/bin"]) { _ in }
        let parts = answer.split(separator: " ").map(String.init)
        #expect(parts.count == 2)
        #expect(parts.last == "0", "there is no project for the tool to read")
        #expect(parts.first?.contains("floe-answer-") == true)
        #expect(!FileManager.default.fileExists(atPath: parts.first ?? "/"))
    }

    @Test func theErrorLineIsThrownAndNotTheExitCode() async throws {
        let tool = try script("printf '%s\\n' '\(Self.error)'; exit 1")
        defer { try? FileManager.default.removeItem(at: tool) }
        do {
            _ = try await TextGeneration.run("hi", engine: .opencode(executable: tool, model: "nope/nope"), environment: ["PATH": "/usr/bin:/bin"]) { _ in }
            Issue.record("the run should have failed")
        } catch {
            #expect(error.localizedDescription == "Unexpected server error. Check server logs for details.")
        }
    }

    @Test func stepsWithoutTextAreAnEmptyAnswer() async throws {
        let tool = try script("printf '%s\\n' '\(Self.stepStart)' '\(Self.stepFinish)'")
        defer { try? FileManager.default.removeItem(at: tool) }
        do {
            _ = try await TextGeneration.run("hi", engine: .opencode(executable: tool, model: nil), environment: ["PATH": "/usr/bin:/bin"]) { _ in }
            Issue.record("the run should have failed")
        } catch {
            #expect(error.localizedDescription == "The model gave no answer.")
        }
    }
}
