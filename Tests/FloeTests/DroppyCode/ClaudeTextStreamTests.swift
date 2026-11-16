//
//  ClaudeTextStreamTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

struct ClaudeTextStreamTests {
    private func delta(_ text: String) -> String {
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}}"#
    }

    /// A stand-in for the tool: a script that ignores its arguments, reads the prompt and prints the lines.
    private func fakeTool(_ body: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-fake-claude-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\ncat > /dev/null\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    // MARK: Lines

    @Test func aTextDeltaIsText() {
        #expect(ClaudeTextStream.event(in: delta("Hello")) == .text("Hello"))
    }

    @Test(arguments: [
        #"{"type":"system","subtype":"init","session_id":"1"}"#,
        #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"m"}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hm"}}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}"#,
        "not json",
        "",
    ])
    func aLineWithNothingToShowIsSkipped(line: String) {
        #expect(ClaudeTextStream.event(in: line) == nil)
    }

    @Test func theResultLineCarriesTheWholeAnswerOrTheToolsOwnError() {
        #expect(ClaudeTextStream.event(in: #"{"type":"result","subtype":"success","is_error":false,"result":"Hello there"}"#) == .result("Hello there"))
        #expect(ClaudeTextStream.event(in: #"{"type":"result","subtype":"success","is_error":true,"result":"Please run /login"}"#) == .failure("Please run /login"))
        #expect(ClaudeTextStream.event(in: #"{"type":"result","subtype":"error_during_execution","errors":["first","second"]}"#) == .failure("first\nsecond"))
        #expect(ClaudeTextStream.event(in: #"{"type":"result","subtype":"error_max_turns"}"#) == .failure("Claude stopped before finishing."))
    }

    @Test func theAnswerIsTheResultLineOrElseWhatWasStreamed() {
        var answer = ToolTextStream.Answer()
        #expect(answer.take(ClaudeTextStream.event(in: delta("Hel"))) == "Hel")
        #expect(answer.take(ClaudeTextStream.event(in: delta("lo "))) == "lo ")
        #expect(answer.take(ClaudeTextStream.event(in: "noise")) == nil)
        #expect(answer.text == "Hello", "without a result line the streamed text stands")
        #expect(answer.take(ClaudeTextStream.event(in: #"{"type":"result","subtype":"success","is_error":false,"result":"Hello, whole."}"#)) == nil)
        #expect(answer.text == "Hello, whole.")
        #expect(answer.failure == nil)
    }

    @Test func theArgumentsAskForAStreamAndKeepTheOneShotRunsLimits() {
        let arguments = ClaudeTextStream.arguments(model: nil)
        #expect(arguments.starts(with: ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]))
        #expect(arguments.contains("haiku"))
        #expect(ClaudeTextStream.arguments(model: "sonnet").contains("sonnet"))
        // What keeps the one-shot run from touching anything is kept for the streamed one.
        let oneShot = TextGeneration.arguments(for: .claude(executable: URL(fileURLWithPath: "/claude"), model: nil), output: URL(fileURLWithPath: "/out"))
        for flag in ["--tools", "--disable-slash-commands", "--strict-mcp-config", "--permission-mode", "dontAsk", "--no-session-persistence"] {
            #expect(oneShot.contains(flag))
            #expect(arguments.contains(flag))
        }
    }

    // MARK: A run, against a script that prints what the tool would

    @Test func textIsHandedOnAsTheToolPrintsItAndTheResultIsTheAnswer() async throws {
        let tool = try fakeTool("""
        printf '%s\\n' '\(delta("Hel"))'
        printf '%s\\n' '\(delta("lo"))'
        printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"Hello"}'
        """)
        defer { try? FileManager.default.removeItem(at: tool) }
        let pieces = Mutex<[String]>([])
        let answer = try await ClaudeTextStream.run("hi", executable: tool, model: nil, environment: [:]) { text in
            pieces.withLock { $0.append(text) }
        }
        #expect(answer == "Hello")
        #expect(pieces.withLock { $0.joined() } == "Hello")
    }

    @Test func aResultWithoutAFinalNewlineIsStillRead() async throws {
        let tool = try fakeTool(#"printf '%s' '{"type":"result","subtype":"success","is_error":false,"result":"Whole"}'"#)
        defer { try? FileManager.default.removeItem(at: tool) }
        let answer = try await ClaudeTextStream.run("hi", executable: tool, model: nil, environment: [:]) { _ in }
        #expect(answer == "Whole")
    }

    @Test func theToolsOwnErrorIsThrown() async throws {
        let tool = try fakeTool(#"printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"result":"Please run /login"}'; exit 1"#)
        defer { try? FileManager.default.removeItem(at: tool) }
        await #expect(throws: ShellError.self) {
            try await ClaudeTextStream.run("hi", executable: tool, model: nil, environment: [:]) { _ in }
        }
        do {
            _ = try await ClaudeTextStream.run("hi", executable: tool, model: nil, environment: [:]) { _ in }
        } catch {
            #expect(error.localizedDescription == "Please run /login")
        }
    }

    @Test func aToolThatFailsWithoutAResultSaysWhatItPrinted() async throws {
        let tool = try fakeTool("echo 'not signed in' >&2; exit 2")
        defer { try? FileManager.default.removeItem(at: tool) }
        do {
            _ = try await ClaudeTextStream.run("hi", executable: tool, model: nil, environment: [:]) { _ in }
            Issue.record("the run should have failed")
        } catch {
            #expect(error.localizedDescription == "not signed in")
        }
    }

    /// Not timed, since a busy test run stalls for seconds: a run that waited for the tool would pass the time limit.
    @Test(.timeLimit(.minutes(2))) func cancellingTheTaskStopsTheTool() async throws {
        let tool = try fakeTool("printf '%s\\n' '\(delta("start"))'\nexec sleep 600")
        defer { try? FileManager.default.removeItem(at: tool) }
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let run = Task {
            try await ClaudeTextStream.run("hi", executable: tool, model: nil, environment: [:]) { _ in signal.yield() }
        }
        for await _ in started {
            break
        }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
    }
}
