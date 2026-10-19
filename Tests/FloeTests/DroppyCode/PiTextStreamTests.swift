//
//  PiTextStreamTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// The `observed` lines are what `pi -p --mode json` printed on a Mac with pi 1.0.2 (the folder shortened), where every run was
/// refused by its provider. The `documented` lines are the examples in pi's own docs/json.md for an answer.
struct PiTextStreamTests {
    private nonisolated enum Observed {
        static let session = #"{"type":"session","version":3,"id":"01a10979-a7ec-72ee-a575-2e265a17290d","timestamp":"2026-10-05T00:32:10.220Z","cwd":"/private/var/folders/1r/T/floe-pi-empty"}"#
        static let agentStart = #"{"type":"agent_start"}"#
        static let turnStart = #"{"type":"turn_start"}"#
        static let system = #"{"type":"message_end","message":{"role":"system","content":"","sections":{"preamble":"Answer the question directly. You have no tools.","cwd":"<cwd>\n/private/var/folders/1r/T/floe-pi-empty\n</cwd>"},"timestamp":1791160330249}}"#
        static let user = #"{"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"Reply with exactly: ok"}],"timestamp":1791160330249}}"#
        static let refusedStart = #"{"type":"message_start","message":{"role":"assistant","content":[],"api":"openai-completions","provider":"opencode","model":"fledge-alpha-free","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"stopReason":"error","timestamp":1791160330253,"errorMessage":"403: {\"type\":\"FreeTierError\",\"message\":\"OpenCode's free tier can only be used from within OpenCode\"}","thinkingLevel":"high"}}"#
        static let refused = #"{"type":"message_end","message":{"role":"assistant","content":[],"api":"openai-completions","provider":"opencode","model":"fledge-alpha-free","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"stopReason":"error","timestamp":1791160330253,"errorMessage":"403: {\"type\":\"FreeTierError\",\"message\":\"OpenCode's free tier can only be used from within OpenCode\"}","thinkingLevel":"high"}}"#
        static let refusedMessage = #"403: {"type":"FreeTierError","message":"OpenCode's free tier can only be used from within OpenCode"}"#
        static let retryStart = #"{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"403: {\"type\":\"server_error\",\"message\":\"Upstream request failed: Model access is disabled\"}"}"#
        static let entryAppended = #"{"type":"entry_appended","entry":{"type":"context_edit","id":"cb2e0a78","parentId":"512cfdc6","timestamp":"2026-10-05T00:31:45.504Z","targetId":"512cfdc6","replacement":null}}"#
        static let retryEnd = #"{"type":"auto_retry_end","success":false,"attempt":3,"finalError":"403: {\"type\":\"server_error\",\"message\":\"Upstream request failed: Model access is disabled\"}"}"#
        static let settled = #"{"type":"agent_settled"}"#
        /// The first line of standard error, with exit code 1, when a sign-in had expired. A stack trace followed it.
        static let expired = "OAuth refresh failed for anthropic: Anthropic token refresh request failed."
    }

    private nonisolated enum Documented {
        static let delta = #"{"type":"message_update","usage":{"input":100,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":101,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello "}}"#
        static let second = #"{"type":"message_update","usage":{},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"there"}}"#
        static let thinking = #"{"type":"message_update","usage":{},"assistantMessageEvent":{"type":"thinking_delta","contentIndex":0,"delta":"hm"}}"#
        static let textEnd = #"{"type":"message_update","usage":{},"assistantMessageEvent":{"type":"text_end","contentIndex":0,"content":"Hello there"}}"#
        static let finished = #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":"Hello there"}],"stopReason":"stop"}}"#
        static let toolStart = #"{"type":"tool_execution_start","toolCallId":"call_abc123","toolName":"bash","args":{"command":"ls -la"}}"#
    }

    private let tool = URL(fileURLWithPath: "/Users/someone/.bun/bin/pi")

    // MARK: Arguments and environment

    @Test func itRunsOnePromptWithNoToolsNoSessionAndNothingOfTheProjects() {
        let arguments = TextGeneration.arguments(for: .pi(executable: tool, model: nil), output: URL(fileURLWithPath: "/tmp/floe-answer-1"))
        #expect(arguments.starts(with: ["-p", "--mode", "json"]))
        for flag in ["--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-context-files", "--no-approve"] {
            #expect(arguments.contains(flag))
        }
        #expect(Array(arguments.suffix(2)) == ["--system-prompt", TextGeneration.instructions], "a short prompt in place of the coding one")
        #expect(!arguments.contains("--model"), "with no model typed, pi's own default stands")
    }

    @Test func theModelIsPassedAsWritten() {
        let arguments = TextGeneration.arguments(for: .pi(executable: tool, model: "opencode/deepseek-v4-flash"), output: URL(fileURLWithPath: "/tmp"))
        #expect(Array(arguments.suffix(2)) == ["--model", "opencode/deepseek-v4-flash"])
    }

    @Test func nothingApprovesAProjectsFilesOrTurnsAToolOn() {
        let arguments = TextGeneration.arguments(for: .pi(executable: tool, model: "a/b"), output: URL(fileURLWithPath: "/tmp"))
        for flag in ["--approve", "-a", "--tools", "-t", "--extension", "-e", "--continue", "-c", "--resume", "-r", "--session", "--api-key"] {
            #expect(!arguments.contains(flag))
        }
    }

    @Test func theEnvironmentIsTheLoginShellsWithoutTheVersionCheck() {
        let folder = URL(fileURLWithPath: "/tmp/floe-answer-1")
        let launch = TextGeneration.launch(.pi(executable: tool, model: nil), in: folder, environment: ["PATH": "/usr/bin", "PI_CODING_AGENT_DIR": "/elsewhere"])
        #expect(launch.environment == ["PATH": "/usr/bin", "PI_CODING_AGENT_DIR": "/elsewhere", "PI_SKIP_VERSION_CHECK": "1"])
        #expect(launch.directory == folder)
        #expect(launch.timeout == 180)
    }

    // MARK: Lines

    @Test func aTextDeltaIsText() {
        #expect(PiTextStream.event(in: Documented.delta) == .text("Hello "))
    }

    @Test func theFinishedMessageIsTheWholeAnswerWithoutItsThinking() {
        #expect(PiTextStream.event(in: Documented.finished) == .result("Hello there"))
    }

    @Test func aRefusedMessageIsTheProvidersOwnWords() {
        #expect(PiTextStream.event(in: Observed.refused) == .failure(Observed.refusedMessage))
        #expect(PiTextStream.event(in: #"{"type":"message_end","message":{"role":"assistant","content":[],"stopReason":"aborted"}}"#) == .failure("pi stopped before finishing."))
    }

    @Test(arguments: [
        Observed.session, Observed.agentStart, Observed.turnStart, Observed.system, Observed.user, Observed.refusedStart,
        Observed.retryStart, Observed.entryAppended, Observed.retryEnd, Observed.settled, Observed.expired,
        Documented.thinking, Documented.textEnd,
        #"{"type":"message_update","assistantMessageEvent":"text_delta"}"#,
        #"{"type":"message_end","message":"assistant"}"#,
        "not json",
        "",
    ])
    func aLineWithNothingToShowIsSkipped(line: String) {
        #expect(PiTextStream.event(in: line) == nil)
    }

    @Test func aToolStartingStopsTheRun() {
        guard case let .stop(message) = PiTextStream.event(in: Documented.toolStart) else {
            Issue.record("a tool starting should stop the run")
            return
        }
        #expect(message.contains("pi tried to use a tool"))
        #expect(message.contains("Settings › AI"))
    }

    @Test func anAnswerAfterRefusalsIsTheAnswer() {
        var answer = ToolTextStream.Answer()
        for line in [Observed.session, Observed.refused, Observed.retryStart, Documented.delta, Documented.second, Documented.finished, Observed.settled] {
            _ = answer.take(PiTextStream.event(in: line))
        }
        #expect(answer.failure == nil)
        #expect(answer.text == "Hello there")
    }

    // MARK: A run, against a script that prints what the tool printed

    private func script(_ lines: [String], then rest: String = "") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-fake-pi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The lines hold quotes of both kinds, so the script prints them from a file beside it.
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: folder.appendingPathComponent("lines"))
        let file = folder.appendingPathComponent("pi")
        try Data("#!/bin/sh\ncat > /dev/null\ncat \"$(dirname \"$0\")/lines\"\n\(rest)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private func failure(of tool: URL) async -> String? {
        defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
        do {
            _ = try await TextGeneration.run("hi", engine: .pi(executable: tool, model: nil), environment: ["PATH": "/usr/bin:/bin"]) { _ in }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test func textIsHandedOnAsItArrivesAndTheFinishedMessageIsTheAnswer() async throws {
        let tool = try script([Observed.session, Observed.agentStart, Observed.system, Observed.user, Documented.delta, Documented.second, Documented.finished, Observed.settled])
        defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
        let pieces = Mutex<[String]>([])
        let threads = ThreadLog()
        let answer = try await TextGeneration.run("hi", engine: .pi(executable: tool, model: nil), environment: ["PATH": "/usr/bin:/bin"]) { text in
            threads.note("text")
            pieces.withLock { $0.append(text) }
        }
        #expect(answer == "Hello there")
        #expect(pieces.withLock { $0 } == ["Hello ", "there"])
        #expect(threads.onMain == ["text": false], "the tool's lines are read off the main thread")
    }

    @Test func aRunTheProviderRefusedFailsWithItsWordsThoughPiExitsWithZero() async throws {
        let tool = try script([Observed.session, Observed.agentStart, Observed.turnStart, Observed.system, Observed.user, Observed.refusedStart, Observed.refused, Observed.settled])
        #expect(await failure(of: tool) == Observed.refusedMessage)
    }

    @Test func anExpiredSignInFailsWithPisMessageAndNotItsStackTrace() async throws {
        let tool = try script([], then: "echo '\(Observed.expired)' >&2; echo '    at postJson (file:///pi/dist/bundle/chunks/anthropic.js:75:6061)' >&2; exit 1")
        #expect(await failure(of: tool) == Observed.expired)
    }

    @Test func aSessionWithNoAssistantMessageIsAnEmptyAnswer() async throws {
        let tool = try script([Observed.session, Observed.agentStart, Observed.system, Observed.user, Observed.settled])
        #expect(await failure(of: tool) == "The model gave no answer.")
    }
}
