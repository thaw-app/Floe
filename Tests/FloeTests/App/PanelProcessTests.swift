@testable import Floe
import Foundation
import Testing

@MainActor
struct PanelProcessTests {
    /// The process fixture never launches Floe or writes its preferences and stores.
    private func child(script: String, arguments: [String] = []) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "panel-fixture"] + arguments
        return process
    }

    /// Waits for asynchronous pipe/exit callbacks with a bounded wall-clock failure.
    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    /// Exercises the real termination handler, not only the lifecycle's pure transition policy.
    @Test func repeatedPreReadyCrashesStopSpawning() async throws {
        var starts = 0
        var exits = 0
        let panel = PanelProcess(environment: .init(
            makeChild: { child(script: "exit 1") },
            prepare: { starts += 1 }
        ))
        panel.onExit = { exits += 1 }
        defer { panel.terminate() }
        panel.request(.show)
        try await wait { exits >= 3 }
        #expect(starts == 3)
        #expect(panel.pid == nil)
    }

    /// A launch error has no termination callback, but still consumes the same bounded retry budget.
    @Test func launchErrorsStopAfterThreeAttemptsAndAllowANewRequest() {
        var attempts = 0
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let panel = PanelProcess(environment: .init(
            makeChild: {
                let child = Process()
                child.executableURL = missing
                return child
            },
            prepare: { attempts += 1 }
        ))
        defer { panel.terminate() }
        panel.request(.show)
        #expect(attempts == 3)
        #expect(panel.pid == nil)
        panel.request(.builtIn("emoji"))
        #expect(attempts == 6, "a later request receives a fresh three-attempt budget")
        #expect(panel.pid == nil)
    }

    /// Retrying Process.run must deliver the pending request rather than replace the lifecycle.
    @Test func aRequestSurvivesALaunchError() async throws {
        var attempts = 0
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ready = try String(decoding: JSONEncoder().encode(PanelPacket.ready), as: UTF8.self)
        let panel = PanelProcess(environment: .init(
            makeChild: {
                if attempts == 1 {
                    let child = Process()
                    child.executableURL = missing
                    return child
                }
                return child(
                    script: "printf '%s\\n' \"$1\"; while IFS= read -r line; do printf '%s\\n' \"$line\"; done",
                    arguments: [ready]
                )
            },
            prepare: { attempts += 1 }
        ))
        var received: [PanelRequest] = []
        panel.onMessage = { packet in
            if case let .request(request, sequence) = packet {
                #expect(sequence == 1)
                received.append(request)
            }
        }
        defer { panel.terminate() }
        panel.request(.show)
        try #require(attempts == 2)
        try await wait { !received.isEmpty }
        #expect(received == [.show])
        panel.terminate()
        try await wait { panel.pid == nil }
    }

    /// SIGTERM-ignoring children must be reaped before a bounded replacement is launched.
    @Test func repeatedReadinessTimeoutsStopSpawningEvenWhenSigtermIsIgnored() async throws {
        var starts = 0
        var children: [Process] = []
        var exits = 0
        let panel = PanelProcess(environment: .init(
            makeChild: {
                let process = child(script: "trap '' TERM; while IFS= read -r line; do :; done")
                children.append(process)
                return process
            },
            prepare: { starts += 1 },
            readinessTimeout: 0.5,
            terminationGrace: 0.05
        ))
        panel.onExit = { exits += 1 }
        defer {
            panel.terminate()
            for child in children where child.isRunning {
                kill(child.processIdentifier, SIGKILL)
            }
        }
        panel.request(.show)
        try await wait { exits >= 3 }
        #expect(starts == 3)
        #expect(panel.pid == nil)
        #expect(children.allSatisfy { !$0.isRunning })
    }

    /// The actual watchdog must retain requests rather than resetting the lifetime before exit.
    @Test func aRequestSurvivesTheFirstChildsReadinessTimeout() async throws {
        var starts = 0
        let ready = try String(decoding: JSONEncoder().encode(PanelPacket.ready), as: UTF8.self)
        let panel = PanelProcess(environment: .init(
            makeChild: {
                if starts == 1 {
                    return child(script: "while IFS= read -r line; do :; done")
                }
                return child(
                    script: "printf '%s\\n' \"$1\"; while IFS= read -r line; do printf '%s\\n' \"$line\"; done",
                    arguments: [ready]
                )
            },
            prepare: { starts += 1 },
            readinessTimeout: 0.5,
            terminationGrace: 0.05
        ))
        var received: [PanelRequest] = []
        panel.onMessage = { packet in
            if case let .request(request, sequence) = packet {
                #expect(sequence == received.count + 1)
                received.append(request)
            }
        }
        defer { panel.terminate() }
        panel.request(.show)
        panel.request(.builtIn("emoji"))
        try await wait { received.count >= 2 }
        #expect(starts == 2)
        #expect(received == [.show, .builtIn("emoji")])
        panel.terminate()
        try await wait { panel.pid == nil }
        #expect(starts == 2, "shutdown must not relaunch the foreground")
    }
}
