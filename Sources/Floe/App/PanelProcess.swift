//
//  PanelProcess.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Owns one disposable foreground process. The resident never constructs a SwiftUI hosting view.
final class PanelProcess {
    struct Environment {
        var makeChild: () -> Process = {
            let child = Process()
            child.executableURL = Bundle.main.executableURL
            child.arguments = ["--panel"]
            return child
        }

        var prepare: () -> Void = {
            UsageStore.shared.flush()
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        }

        var readinessTimeout: TimeInterval = 10
        var terminationGrace: TimeInterval = 1
    }

    private let environment: Environment
    private var lifetime = PanelLifetime()
    private var process: Process?
    private var channel: PanelChannel?
    private var stopping = false
    var onMessage: ((PanelPacket) -> Void)?
    var onExit: (() -> Void)?

    /// Allows lifecycle tests to use owned fixture children without touching persistent app state.
    init(environment: Environment = Environment()) {
        self.environment = environment
    }

    var pid: Int32? {
        process?.isRunning == true ? process?.processIdentifier : nil
    }

    /// Starts the foreground lazily, or queues work behind its current startup or shutdown.
    func request(_ request: PanelRequest) {
        guard !stopping else { return }
        apply(lifetime.request(request))
    }

    /// State updates do not launch a process or count as a request to keep its UI open.
    func send(_ packet: PanelPacket) {
        channel?.send(packet)
    }

    /// Executes the lifecycle decisions without duplicating its retry and readiness state.
    private func apply(_ effects: [PanelLifetime.Effect]) {
        for effect in effects {
            switch effect {
            case .start: start()
            case .terminate: terminateUnreadyChild()
            case let .send(message): channel?.send(message.packet)
            }
        }
    }

    /// Launches the same executable with private pipes after flushing resident-owned settings.
    private func start() {
        environment.prepare()
        let child = environment.makeChild()
        let input = Pipe()
        let output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, self.process === ended else { return }
                self.channel?.close()
                self.channel = nil
                self.process = nil
                self.onExit?()
                if !self.stopping {
                    self.apply(self.lifetime.exited())
                }
            }
        }
        do {
            try child.run()
            process = child
            DispatchQueue.main.asyncAfter(deadline: .now() + environment.readinessTimeout) { [weak self, weak child] in
                guard let self, let child, self.process === child, child.isRunning else { return }
                self.apply(self.lifetime.readinessTimedOut())
            }
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            let channel = PanelChannel(input: output.fileHandleForReading, output: input.fileHandleForWriting)
            self.channel = channel
            channel.receive = { [weak self] packet in self?.receive(packet) }
            channel.onClose = { [weak child] in
                if child?.isRunning == true {
                    child?.terminate()
                }
            }
            channel.start()
        } catch {
            lifetime = PanelLifetime()
            NSLog("Floe could not start its panel: \(error.localizedDescription)")
        }
    }

    /// A hung child may not service SIGTERM; only that still-owned child is killed after grace.
    private func terminateUnreadyChild() {
        guard let child = process, child.isRunning else { return }
        child.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + environment.terminationGrace) { [weak self, weak child] in
            guard let self, let child, self.process === child, child.isRunning else { return }
            kill(child.processIdentifier, SIGKILL)
        }
    }

    /// Handles lifecycle packets here and forwards state mutations to their resident owners.
    private func receive(_ packet: PanelPacket) {
        switch packet {
        case .ready:
            guard lifetime.isAwaitingReadiness else { return }
            onMessage?(packet)
            apply(lifetime.ready())
        case let .idle(sequence):
            apply(lifetime.idle(sequence: sequence))
        default:
            onMessage?(packet)
        }
    }

    /// Stops the owned child and refuses further launch requests during resident shutdown.
    func terminate() {
        stopping = true
        channel?.send(.shutdown)
        if let process, process.isRunning {
            process.terminate()
        }
        channel?.close()
    }
}
