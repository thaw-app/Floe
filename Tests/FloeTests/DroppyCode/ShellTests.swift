//
//  ShellTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Runs the small tools every Mac has, so the process, its pipes and its deadline are the real ones.
struct ShellTests {
    private func tool(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test func collectsWhatTheProcessPrintsAndItsStatus() async throws {
        let result = try await Shell.run(tool("/bin/sh"), ["-c", "printf out; printf err >&2; exit 3"], environment: [:])
        #expect(result.status == 3)
        #expect(!result.succeeded)
        #expect(result.output == "out")
        #expect(result.errorOutput == "err")
    }

    @Test func writesTheInputToTheProcess() async throws {
        let result = try await Shell.run(tool("/bin/cat"), [], environment: [:], input: Data("  typed\n".utf8))
        #expect(result.succeeded)
        #expect(result.output == "  typed\n")
        #expect(result.trimmedOutput == "typed")
    }

    @Test func aProgramThatEndsWithoutReadingItsInputDoesNotEndTheCaller() async throws {
        // More than a pipe holds, so the write is still under way when the program is gone.
        let result = try await Shell.run(tool("/usr/bin/true"), [], environment: [:], input: Data(count: 1 << 20))
        #expect(result.succeeded)
    }

    @Test func runsInTheDirectoryAndEnvironmentItIsGiven() async throws {
        let directory = URL(fileURLWithPath: "/usr/bin")
        let result = try await Shell.run(tool("/bin/sh"), ["-c", "pwd -P; printf %s \"$GREETING\""], in: directory, environment: ["GREETING": "hello"])
        #expect(result.output == "\(directory.path)\nhello")
    }

    @Test func stopsAProcessThatOutlivesItsDeadline() async throws {
        let started = Date()
        let result = try await Shell.run(tool("/bin/sleep"), ["60"], environment: [:], timeout: 0.2)
        #expect(!result.succeeded)
        // Well under the minute: a busy CI runner has taken 13 seconds to stop it.
        #expect(Date().timeIntervalSince(started) < 30)
    }

    @Test func aProcessThatClosesItsOwnStreamsKeepsRunningToItsEnd() async throws {
        // A command that closes its own output is not over because its pipes are: no deadline may
        // tear it down for streams that ended while it went on living.
        let started = Date()
        let result = try await Shell.run(tool("/bin/sh"), ["-c", "exec 1>&- 2>&-; sleep 1"], environment: [:], timeout: 5)
        #expect(result.succeeded)
        #expect(Date().timeIntervalSince(started) >= 0.9)
    }

    @Test func keepsOnlyTheTailOfALongOutput() async throws {
        let result = try await Shell.run(tool("/bin/sh"), ["-c", "yes 0123456789 | head -c 100000"], environment: [:], outputLimit: 1000)
        #expect(result.stdout.count <= 2000)
        #expect(result.stdout.count >= 1000)
    }

    @Test func aMissingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await Shell.run(tool("/nonexistent/tool"), [], environment: [:])
        }
    }

    @Test func cancellingTheTaskStopsTheProcess() async {
        let running = Task { try await Shell.run(tool("/bin/sleep"), ["30"], environment: [:]) }
        try? await Task.sleep(for: .milliseconds(100))
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
    }

    @Test func aToolThatIsNotOnThePathIsReportedByName() async {
        await #expect(throws: ShellError.self) {
            try await Shell.run(tool: "floe-no-such-tool", [])
        }
        #expect(ShellError("gone").errorDescription == "gone")
    }

    @Test(arguments: [
        ("out", "err", "err"),
        ("out\n", "  ", "out"),
        ("", "", "The command failed with exit code 2."),
    ])
    func theFailureMessagePrefersWhatTheToolSaidOnStandardError(output: String, error: String, message: String) {
        let result = ShellResult(status: 2, stdout: Data(output.utf8), stderr: Data(error.utf8))
        #expect(result.failureMessage == message)
    }
}
