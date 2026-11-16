//
//  BackgroundScheduler.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Foundation

/// Runs interval commands in the background: menu-bar commands refresh their status item,
/// no-view commands run once per tick without opening the panel.
@MainActor final class BackgroundScheduler {
    private let model: LauncherModel
    private let menuBarCommands: MenuBarCommands
    private(set) var timers: [String: Timer] = [:]
    private var intervals: [String: TimeInterval] = [:]
    private(set) var runs: [String: ExtensionSession] = [:]
    /// Starts a run's host. A test leaves it unstarted and plays the host's part.
    var startsHost: (ExtensionSession) -> Void = { $0.start() }

    /// There is one, so it also answers `launchCommand`.
    init(model: LauncherModel, menuBarCommands: MenuBarCommands) {
        self.model = model
        self.menuBarCommands = menuBarCommands
        CommandLauncher.shared = CommandLauncher(
            commands: { [weak model] in model?.commands ?? [] },
            userInitiated: { [weak model] command, arguments, context in model?.runner.run(command, arguments: arguments, context: context) },
            background: { [weak self] command, arguments, context in self?.launch(command, arguments: arguments, context: context) }
        )
    }

    /// Reschedules every enabled command with an interval; commands that can't run unattended
    /// (missing required preferences or arguments) are never scheduled.
    func sync(_ commands: [ExtensionCommand]) {
        let wanted = commands.filter { $0.interval != nil && model.canRunUnattended($0) }
        let ids = Set(wanted.map(\.id))
        for id in timers.keys where !ids.contains(id) {
            timers[id]?.invalidate()
            timers.removeValue(forKey: id)
            intervals.removeValue(forKey: id)
            if let run = runs.removeValue(forKey: id) {
                run.forceStop()
            }
        }
        for command in wanted {
            guard let interval = command.interval else { continue }
            if timers[command.id] != nil, intervals[command.id] == interval {
                continue
            }
            timers[command.id]?.invalidate()
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.fire(command) }
            }
            timer.tolerance = interval * 0.1
            timers[command.id] = timer
            intervals[command.id] = interval
        }
    }

    func stopAll() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
        intervals.removeAll()
        for run in runs.values {
            run.forceStop()
        }
        runs.removeAll()
    }

    func fire(_ command: ExtensionCommand) {
        let command = model.enabledCommands.first(where: { $0.id == command.id }) ?? command
        guard model.canRunUnattended(command) else { return }
        if command.mode == "menu-bar" {
            menuBarCommands.refresh(command)
            return
        }
        guard command.mode == "no-view" else { return }
        start(command)
    }

    /// `launchCommand` with the background type: a menu-bar command refreshes, a no-view one runs once.
    func launch(_ command: ExtensionCommand, arguments: [String: Any], context: [String: Any]?) {
        guard model.canRunUnattended(command, arguments: arguments) else { return }
        if command.mode == "menu-bar" {
            menuBarCommands.refresh(command)
        } else if command.mode == "no-view" {
            start(command, arguments: arguments, context: context)
        }
    }

    /// One run of a no-view command, unless one is still going or starting; stopped after a minute.
    private func start(_ command: ExtensionCommand, arguments: [String: Any] = [:], context: [String: Any]? = nil) {
        if let run = runs[command.id], !run.hasEnded, !run.isStopping {
            return
        }
        let session = ExtensionSession(command: command, arguments: arguments, launchType: "background", launchContext: context)
        session.onMessage = { [weak self, weak session] message in
            guard let self, let session else { return }
            // In the background closeMainWindow has no window to close and the run goes on, as in Raycast.
            switch message["type"] as? String {
            case "exit", "crashed":
                session.forceStop()
                if runs[command.id] === session {
                    runs.removeValue(forKey: command.id)
                }
            case "hud", "open", "copy", "paste":
                model.runner.handleBackgroundMessage(message)
            default:
                break
            }
        }
        session.answer = ExtensionRunner.answer(withHistory: model.runner.host.clipboardHistory)
        runs[command.id] = session
        startsHost(session)
        DispatchQueue.main.asyncAfter(deadline: .now() + ExtensionSession.unattendedLimit) { [weak self, weak session] in
            guard let self, let session else { return }
            if !session.hasEnded {
                session.forceStop()
            }
            if runs[command.id] === session {
                runs.removeValue(forKey: command.id)
            }
        }
    }
}
