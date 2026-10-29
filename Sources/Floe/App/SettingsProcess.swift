//
//  SettingsProcess.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import CryptoKit

/// The launcher's handle on its settings process: this executable again, started with `--settings`.
/// One runs at a time, it ends by itself when its window closes, and it never outlives the launcher.
final class SettingsProcess {
    /// What opening Settings comes to.
    enum Step: Equatable {
        /// No settings process runs: start one with these arguments.
        case start(arguments: [String])
        /// One runs: ask it to come to the front, on this page if one is named.
        case bringForward(page: String)
    }

    /// `page` is a `SettingsPage.id`; without one a new process opens where the last one was left.
    static func step(isRunning: Bool, page: String?, lastPage: String?) -> Step {
        if isRunning {
            return .bringForward(page: page ?? "")
        }
        return .start(arguments: ["--settings"] + ((page ?? lastPage).map { ["--page", $0] } ?? []))
    }

    private var process: Process?
    private var processKey: SymmetricKey?
    /// The page the settings window last showed, reported by the settings process.
    var lastPage: String?
    /// Called on the main thread when the process has ended, however it ended.
    var onExit: () -> Void = { /* set by the link */ }
    /// Asks the running process to come forward.
    var bringForward: (String) -> Void = { _ in
        // Set by the link, which owns the messages.
    }

    /// The running settings process, which is the only sender the launcher listens to.
    var pid: Int32? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    /// The key the running settings process signs its messages with (see `LinkKey`).
    var key: SymmetricKey? {
        pid == nil ? nil : processKey
    }

    func show(page: String?) {
        switch Self.step(isRunning: pid != nil, page: page, lastPage: lastPage) {
        case let .start(arguments):
            start(arguments)
        case let .bringForward(page):
            bringForward(page)
            activate()
        }
    }

    /// The settings process activates itself too; this covers the case where the system holds it back.
    func activate() {
        pid.flatMap(NSRunningApplication.init(processIdentifier:))?.activate()
    }

    private func start(_ arguments: [String]) {
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let key = LinkKey.make()
        let input = Pipe()
        // A settings process that ends before it reads the key makes the write fail, not end Floe with a broken pipe.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = input
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self else { return }
                // A process that crashed is simply gone: the next opening starts a new one.
                if self.process === ended {
                    self.process = nil
                }
                self.onExit()
            }
        }
        do {
            try process.run()
            self.process = process
            processKey = key
            try input.fileHandleForWriting.write(contentsOf: LinkKey.encoded(key))
            try input.fileHandleForWriting.close()
        } catch {
            // A settings process without its key cannot reach the launcher, so it is not left running.
            if process.isRunning {
                process.terminate()
            }
            NSLog("Floe could not start its settings process: \(error.localizedDescription)")
        }
    }

    /// Ends the settings process with the launcher. It also watches for the launcher's exit itself.
    func terminate() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}

/// Whether the launcher's global hotkeys stand down for a recorder in the settings process.
struct RemoteRecording: Equatable {
    private(set) var isRecording = false

    mutating func received(_ isRecording: Bool) {
        self.isRecording = isRecording
    }

    /// A settings process that dies while recording never says it stopped.
    mutating func settingsProcessExited() {
        isRecording = false
    }
}
