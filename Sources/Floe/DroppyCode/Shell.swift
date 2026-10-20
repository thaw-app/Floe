//
//  Shell.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Core/Support/Shell.swift, and modified: the login shell
//  environment moved to LoginEnvironment.swift, the check for shell commands that write files
//  is left out, because Floe runs no agent's commands, and `run` can hand standard output on
//  as it is read, for a tool that streams its answer. Input written to a program that has already
//  ended fails quietly, where it used to end the app with a broken pipe. The process itself is
//  Subprocess's now, as the extension installer already runs; what stays here is the tail-keeping
//  collector, the deadline, and the quiet treatment of a broken pipe.

import Foundation
import Subprocess
import Synchronization
import System

nonisolated struct ShellResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var succeeded: Bool {
        status == 0
    }

    var output: String {
        // A tool's output is not always valid UTF-8; what can't be read is replaced, not dropped.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: stdout, as: UTF8.self)
    }

    var errorOutput: String {
        // A tool's output is not always valid UTF-8; what can't be read is replaced, not dropped.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: stderr, as: UTF8.self)
    }

    var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The most useful text to show when a command fails.
    var failureMessage: String {
        let error = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = error.isEmpty ? trimmedOutput : error
        return message.isEmpty ? String(localized: "The command failed with exit code \(status).", bundle: .floe, comment: "The placeholder is the number a command ended with.") : message
    }
}

nonisolated struct ShellError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? {
        message
    }

    init(_ message: String) {
        self.message = message
    }
}

nonisolated enum Shell {
    /// Runs a process to completion off the main actor and collects its output. With an
    /// `outputLimit`, only that many bytes of each stream's tail are kept. `onOutput` is given
    /// standard output as it is read, in order.
    @concurrent
    static func run(
        _ executable: URL,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval = 120,
        outputLimit: Int? = nil,
        onOutput: (@Sendable (Data) -> Void)? = nil
    ) async throws -> ShellResult {
        try Task.checkCancellation()
        // A program that is not there, or cannot run, is said at once instead of asked of the process machinery.
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ShellError(String(localized: "\(executable.lastPathComponent) could not be run.", bundle: .floe, comment: "The placeholder is the name of the command that could not run."))
        }
        let collector = OutputCollector(limit: outputLimit, onOutput: onOutput)
        // A cancel tears the process down through these steps, and so does the deadline below.
        // The process alone is asked, never Floe's own group, as terminate() did.
        var options = PlatformOptions()
        let teardown = [TeardownStep.gracefulShutDown(allowedDurationToNextStep: .seconds(1))]
        options.teardownSequence = teardown
        // The body hands the running process over, for the deadline to end when it outlives its time.
        let running = Mutex<Execution<FileDescriptorInput, SequenceOutput, SequenceOutput>?>(nil)
        let surroundings = environment ?? LoginEnvironment.current
        // The input goes through a pipe of Floe's own, whose write end is made quiet, so a program
        // that ends without reading it fails the write instead of ending Floe. Without input: the null device.
        let stdin = try StandardInput(for: input)
        let deadline = Task {
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch {
                // Cancelled because the process has ended: only a real deadline tears
                // a living process down, however its streams ended before it did.
                return
            }
            await running.withLock { $0 }?.teardown(using: teardown)
        }
        // The process has ended, one way or another: its deadline is of no more use.
        defer { deadline.cancel() }

        let result: ExecutionResult<Void, SequenceOutput, SequenceOutput>
        do {
            result = try await Subprocess.run(
                .path(FilePath(executable.path)),
                arguments: Arguments(arguments),
                environment: .custom(Dictionary(uniqueKeysWithValues: surroundings.map { (Environment.Key(stringLiteral: $0.key), $0.value) })),
                workingDirectory: directory.map { FilePath($0.path) },
                platformOptions: options,
                input: .fileDescriptor(stdin.readEnd, closeAfterSpawningProcess: false),
                output: .sequence,
                error: .sequence
            ) { execution in
                // The child has its own copy of the read end; Floe's goes at once.
                stdin.closeReadEnd()
                running.withLock { $0 = execution }
                await exchange(with: execution, input: input, stdin: stdin, collector: collector)
                stdin.close()
            }
        } catch {
            stdin.close()
            throw error
        }
        try Task.checkCancellation()
        // A process ended by a signal carries the signal's number, as it did.
        let status: Int32 = switch result.terminationStatus {
        case let .exited(code): code
        case let .signaled(signal): signal
        }
        return ShellResult(status: status, stdout: collector.output(.stdout), stderr: collector.output(.stderr))
    }

    /// Reads both streams to their ends while the input is written.
    private static func exchange(
        with execution: Execution<FileDescriptorInput, SequenceOutput, SequenceOutput>,
        input: Data?,
        stdin: StandardInput,
        collector: OutputCollector
    ) async {
        await withThrowingTaskGroup { group in
            group.addTask {
                for try await buffer in execution.standardOutput {
                    collector.read(buffer.withUnsafeBytes(Data.init), from: .stdout)
                }
            }
            group.addTask {
                for try await buffer in execution.standardError {
                    collector.read(buffer.withUnsafeBytes(Data.init), from: .stderr)
                }
            }
            if let input {
                group.addTask {
                    // The write is quiet: a program that has ended fails it instead of ending Floe with it.
                    stdin.write([UInt8](input))
                    stdin.close()
                }
            }
        }
    }

    /// Runs a named tool found on the login PATH.
    @concurrent
    static func run(
        tool name: String,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        guard let executable = LoginEnvironment.which(name) else {
            throw ShellError(String(localized: "\(name) was not found on your PATH.", bundle: .floe, comment: "The placeholder is the name of a command, and PATH is the shell variable and stays as written."))
        }
        return try await run(executable, arguments, in: directory, environment: environment, input: input, timeout: timeout)
    }
}

private final nonisolated class OutputCollector: Sendable {
    enum Stream: Hashable {
        case stdout
        case stderr
    }

    private struct State: Sendable {
        var stdout = Data()
        var stderr = Data()
    }

    private let state = Mutex(State())
    private let limit: Int?
    private let onOutput: (@Sendable (Data) -> Void)?

    init(limit: Int?, onOutput: (@Sendable (Data) -> Void)? = nil) {
        self.limit = limit
        self.onOutput = onOutput
    }

    /// Takes one chunk of a stream in, and hands standard output on as it arrived.
    func read(_ data: Data, from stream: Stream) {
        state.withLock { state in
            switch stream {
            case .stdout: append(data, to: &state.stdout)
            case .stderr: append(data, to: &state.stderr)
            }
        }
        if stream == .stdout {
            onOutput?(data)
        }
    }

    /// Keeps the tail within the limit, trimming by whole chunks once the buffer holds twice
    /// the limit, so a stream that never ends costs O(limit) memory and amortized O(1) per byte.
    private func append(_ data: Data, to buffer: inout Data) {
        buffer.append(data)
        guard let limit, buffer.count > limit * 2 else { return }
        buffer = Data(buffer.suffix(limit))
    }

    func output(_ stream: Stream) -> Data {
        state.withLock { stream == .stdout ? $0.stdout : $0.stderr }
    }
}

/// The process's standard input: a pipe of Floe's own when there is input, so its write end can be
/// made quiet, and the null device when there is not. Every end has one owner and is closed once.
private final nonisolated class StandardInput: Sendable {
    let readEnd: FileDescriptor
    private let writeEnd: FileDescriptor?
    private let readClosed = Mutex(false)
    private let writeClosed = Mutex(false)

    init(for input: Data?) throws {
        guard input != nil else {
            readEnd = try FileDescriptor.open("/dev/null", .readOnly)
            writeEnd = nil
            return
        }
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            throw ShellError(String(localized: "The command's input could not be prepared.", bundle: .floe, comment: "Said when a command is given something to read and the pipe to read it from cannot be made."))
        }
        readEnd = FileDescriptor(rawValue: fds[0])
        writeEnd = FileDescriptor(rawValue: fds[1])
        // A write to a pipe whose reader is gone fails quietly, instead of ending Floe with a broken pipe.
        _ = fcntl(fds[1], F_SETNOSIGPIPE, 1)
    }

    /// The child has its own copy of the read end now, so Floe's goes at once, before another
    /// run's file can take the number. Its write end closes only when the writing is done.
    func closeReadEnd() {
        readClosed.withLock { isClosed in
            guard !isClosed else { return }
            isClosed = true
            try? readEnd.close()
        }
    }

    /// Writes the input, in full: a partial write is written on until it is done or the reader is gone.
    func write(_ bytes: [UInt8]) {
        guard let writeEnd else { return }
        _ = try? writeEnd.writeAll(bytes)
    }

    /// Closes what is still Floe's, whichever way the run ends.
    func close() {
        closeReadEnd()
        writeClosed.withLock { isClosed in
            guard !isClosed, let writeEnd else { return }
            isClosed = true
            try? writeEnd.close()
        }
    }
}
