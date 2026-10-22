//
//  ToolTextStreamTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// A script stands in for the tool, and the test says what each of its lines means.
struct ToolTextStreamTests {
    private func launch(_ body: String) throws -> ToolTextStream.Launch {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-fake-tool-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\ncat > /dev/null\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return ToolTextStream.Launch(executable: file, arguments: [], directory: FileManager.default.temporaryDirectory, environment: [:], timeout: 30)
    }

    /// "text:x" is text, "result:x" the whole answer, "failure:x" an error, "stop:x" a stop; anything else is noise.
    private static nonisolated func read(_ line: String) -> ToolTextStream.Event? {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "text": return .text(parts[1])
        case "result": return .result(parts[1])
        case "failure": return .failure(parts[1])
        case "stop": return .stop(parts[1])
        default: return nil
        }
    }

    private func failure(_ body: String) async throws -> String? {
        let launch = try launch(body)
        defer { try? FileManager.default.removeItem(at: launch.executable) }
        do {
            _ = try await ToolTextStream.run("hi", launch: launch, read: Self.read) { _ in }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test func linesAreCutAtNewlinesHoweverTheBytesArrive() {
        var lines = ToolTextStream.Lines()
        #expect(lines.append(Data("one\ntw".utf8)) == ["one"])
        #expect(lines.append(Data("o\nthree\nfo".utf8)) == ["two", "three"])
        #expect(lines.append(Data()).isEmpty)
        #expect(lines.rest() == ["fo"])
        #expect(lines.rest().isEmpty)
    }

    @Test func anAnswerAfterAnErrorIsTheAnswer() {
        var answer = ToolTextStream.Answer()
        #expect(answer.take(.failure("overloaded")) == nil)
        #expect(answer.failure == "overloaded")
        #expect(answer.take(.text("Hel")) == "Hel")
        #expect(answer.take(.result("Hello")) == nil)
        #expect(answer.failure == nil, "the tool tried again and got there")
        #expect(answer.text == "Hello")
        #expect(answer.take(.stop("no tools")) == nil)
        #expect(answer.failure == "no tools")
    }

    @Test func theComplaintIsTheLastLineThatIsNotAStackFrame() {
        #expect(ToolTextStream.complaint(in: "warming up\nnot signed in\n") == "not signed in")
        #expect(ToolTextStream.complaint(in: "OAuth refresh failed for anthropic\n    at postJson (file:///a.js:75:6061)\n    at async refresh (file:///b.js:1:2)\n") == "OAuth refresh failed for anthropic")
        #expect(ToolTextStream.complaint(in: " \n\n") == nil)
        #expect(ToolTextStream.complaint(in: String(repeating: "x", count: 900))?.count == 500)
    }

    @Test func textIsHandedOnAndJunkLinesAreSkipped() async throws {
        let launch = try launch("echo 'text:Hel'; echo 'not a line Floe knows'; echo; echo 'text:lo'")
        defer { try? FileManager.default.removeItem(at: launch.executable) }
        let pieces = Mutex<[String]>([])
        let threads = ThreadLog()
        let read: @Sendable (String) -> ToolTextStream.Event? = { line in
            threads.note("read")
            return Self.read(line)
        }
        let answer = try await ToolTextStream.run("hi", launch: launch, read: read) { text in
            threads.note("text")
            pieces.withLock { $0.append(text) }
        }
        #expect(answer == "Hello")
        #expect(pieces.withLock { $0 } == ["Hel", "lo"])
        #expect(threads.onMain == ["read": false, "text": false], "the tool's lines are read off the main thread")
    }

    @Test func anEmptyAnswerIsAnErrorInTheToolsOwnWordsWhenItHasAny() async throws {
        #expect(try await failure("echo 'step:start'; echo 'step:finish'") == "The model gave no answer.")
        #expect(try await failure("echo 'no provider is set up' >&2") == "no provider is set up")
    }

    @Test func aToolThatFailsSaysItsLastLineAndNotItsStack() async throws {
        #expect(try await failure("echo 'token expired' >&2; echo '    at refresh (file:///a.js:1:2)' >&2; exit 1") == "token expired")
        #expect(try await failure("exit 3") == "The command failed with exit code 3.")
    }

    @Test func anErrorTheToolReportsWinsOverAnAnswerThatStopsShort() async throws {
        #expect(try await failure("echo 'text:Hel'; echo 'failure:403 refused'") == "403 refused", "a tool can exit with 0 after an error")
    }

    @Test func aStopLineEndsTheToolAtOnce() async throws {
        let started = Date()
        #expect(try await failure("echo 'stop:tried a tool'; sleep 60; echo 'text:too late'") == "tried a tool")
        // Well under the minute: a busy CI runner has taken 15 seconds to stop it.
        #expect(Date().timeIntervalSince(started) < 30, "the tool was stopped, not waited for")
    }
}
