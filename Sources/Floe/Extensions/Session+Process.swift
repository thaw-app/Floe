//
//  Session+Process.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Subprocess
import System

/// The half of a session that needs a real Bun process: spawning it, wiring its pipes, and stopping it.
/// What the session does with the messages lives in Session.swift.
extension ExtensionSession {
    func start() {
        guard let bun = Paths.bun else {
            toast = ToastState(id: 0, style: "failure", title: String(localized: "Bun isn't installed", bundle: .floe, comment: "Bun is the name of a tool."), message: "brew install bun")
            return
        }
        let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let environment = hostEnvironment()
        // Cancelling the task sends SIGTERM, then SIGKILL: a host stuck in synchronous code ignores SIGTERM.
        var options = PlatformOptions()
        options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(1))]
        // Messages sent before the host is up wait here until its stdin opens.
        let (outgoing, messages) = AsyncStream<[UInt8]>.makeStream()
        transport = { message in
            guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
            messages.yield(Array(data) + [0x0A])
        }
        // --smol trades some GC headroom for a smaller footprint: extension trees stay mounted for
        // Back and resume, so the allocator's retention is the host's biggest memory cost.
        let hostArguments = Arguments(["--smol", Paths.host.path, command.extensionDir.path, command.name, argumentsJSON])
        // One decoder per host: it owns the partial bytes between chunks and keeps decoding off the main actor.
        let decoder = HostMessageDecoder()
        let started: @Sendable (pid_t) async -> Void = { [weak self] identifier in
            await MainActor.run { [weak self] in self?.hostStarted(identifier) }
        }
        let deliver: @Sendable (DecodedHostMessage) async -> Void = { [weak self] message in
            await MainActor.run { [weak self] in self?.apply(message) }
        }
        let output: @Sendable (Data) async -> Void = { data in
            await decoder.deliver(data, applying: deliver)
        }
        let errors: @Sendable (Data) async -> Void = { [weak self] data in
            await MainActor.run { [weak self] in self?.appendLog(data) }
        }
        hostTask = Task { @concurrent [weak self] in
            do {
                let result = try await Subprocess.run(
                    .path(FilePath(bun)),
                    arguments: hostArguments,
                    environment: environment,
                    platformOptions: options,
                    input: .inputWriter,
                    output: .sequence,
                    error: .sequence
                ) { execution in
                    await started(execution.processIdentifier.value)
                    try await Self.relay(execution, outgoing: outgoing, output: output, errors: errors)
                    // The host closed its output, so nothing more will be read from its input.
                    messages.finish()
                }
                await MainActor.run { [weak self] in self?.hostEnded(result.terminationStatus) }
            } catch {
                messages.finish()
                await MainActor.run { [weak self] in self?.hostFailed(error) }
            }
        }
    }

    /// The login shell's environment, not the app's own: launched from Finder, the app has a PATH
    /// without brew, git or node, and extensions run those.
    private func hostEnvironment() -> Environment {
        let variables = Self.hostVariables(
            LoginEnvironment.current,
            preferences: try? JSONSerialization.data(withJSONObject: PreferenceStore.resolvedValues(for: command)),
            hasAI: AIAnswer.isAvailable(for: command.extensionName),
            launchType: launchType,
            recordsAccess: recordsAccess(),
            isDevelopment: Self.isUnderDevelopment(command.extensionDir)
        )
        return Environment.custom(Dictionary(uniqueKeysWithValues: variables.map { (Environment.Key(stringLiteral: $0.key), $0.value) }))
    }

    /// Feeds the host's stdin and hands on what it prints, until it closes its output.
    /// It holds no session, so a session nobody keeps can go away while its host still runs.
    @concurrent
    private static nonisolated func relay(
        _ execution: Execution<CustomWriteInput, SequenceOutput, SequenceOutput>,
        outgoing: AsyncStream<[UInt8]>,
        output: @escaping @Sendable (Data) async -> Void,
        errors: @escaping @Sendable (Data) async -> Void
    ) async throws {
        let writing = Task {
            for await bytes in outgoing {
                _ = try? await execution.standardInputWriter.write(bytes)
            }
        }
        defer { writing.cancel() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await buffer in execution.standardError {
                    let data = buffer.withUnsafeBytes { Data($0) }
                    FileHandle.standardError.write(data)
                    await errors(data)
                }
            }
            for try await buffer in execution.standardOutput {
                await output(buffer.withUnsafeBytes { Data($0) })
            }
            try await group.waitForAll()
        }
    }

    private func hostStarted(_ identifier: pid_t) {
        processID = identifier
        watchdog = Timer.scheduledOnMain(withTimeInterval: 3, repeats: true) { [weak self] in
            guard let self, processID != nil else { return }
            heartbeat()
        }
    }

    private func hostEnded(_ status: TerminationStatus) {
        processID = nil
        switch status {
        case let .exited(code): processEnded(status: code, wasSignalled: false)
        case let .signaled(signal): processEnded(status: signal, wasSignalled: true)
        }
    }

    /// The host couldn't be launched, or reading from it broke off; stopping it on purpose also ends up here.
    private func hostFailed(_ error: Error) {
        let hadStarted = processID != nil
        processID = nil
        watchdog?.invalidate()
        cancelRequests()
        guard !isStopping, failure == nil else { return }
        let message = hadStarted ? String(localized: "The extension stopped unexpectedly.", bundle: .floe) : String(localized: "The extension couldn't start.", bundle: .floe)
        failure = SessionFailure(kind: hadStarted ? .crashed : .error, message: message, details: error.localizedDescription)
    }

    /// Stops the process, optionally after a grace period so trailing messages still arrive.
    func stop(after delay: TimeInterval = 0) {
        isStopping = true
        resolveAlert(false)
        watchdog?.invalidate()
        cancelRequests()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            hostTask?.cancel()
        }
    }

    /// Kills the process now, for app quit and the self-test, where nothing waits for a grace period.
    func forceStop() {
        isStopping = true
        resolveAlert(false)
        watchdog?.invalidate()
        cancelRequests()
        if let processID {
            kill(processID, SIGKILL)
        }
    }
}
