//
//  PanelProcess.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Owns one disposable foreground process. The resident never constructs a SwiftUI hosting view.
final class PanelProcess {
    private var lifetime = PanelLifetime()
    private var process: Process?
    private var channel: PanelChannel?
    private var stopping = false
    private var ready = false
    var onMessage: (PanelPacket) -> Void = { _ in }
    var onExit: () -> Void = {}

    var pid: Int32? {
        process?.isRunning == true ? process?.processIdentifier : nil
    }

    func request(_ request: PanelRequest) {
        guard !stopping else { return }
        apply(lifetime.request(request))
    }

    /// State updates do not launch a process or count as a request to keep its UI open.
    func send(_ packet: PanelPacket) {
        channel?.send(packet)
    }

    private func apply(_ effects: [PanelLifetime.Effect]) {
        for effect in effects {
            switch effect {
            case .start: start()
            case let .send(message): channel?.send(message.packet)
            }
        }
    }

    private func start() {
        guard let executable = Bundle.main.executableURL else { return }
        UsageStore.shared.flush()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = executable
        child.arguments = ["--panel"]
        child.standardInput = input
        child.standardOutput = output
        child.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, self.process === ended else { return }
                self.channel?.close()
                self.channel = nil
                self.process = nil
                self.onExit()
                if !self.stopping {
                    self.apply(self.lifetime.exited())
                }
            }
        }
        do {
            try child.run()
            process = child
            ready = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak child] in
                guard let self, let child, self.process === child, !self.ready, child.isRunning else { return }
                self.lifetime = PanelLifetime()
                child.terminate()
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

    private func receive(_ packet: PanelPacket) {
        switch packet {
        case .ready:
            ready = true
            onMessage(packet)
            apply(lifetime.ready())
        case let .idle(sequence):
            apply(lifetime.idle(sequence: sequence))
        default:
            onMessage(packet)
        }
    }

    func terminate() {
        stopping = true
        channel?.send(.shutdown)
        if let process, process.isRunning {
            process.terminate()
        }
        channel?.close()
    }
}
