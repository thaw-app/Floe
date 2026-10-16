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
    private var runs: [String: ExtensionSession] = [:]

    init(model: LauncherModel, menuBarCommands: MenuBarCommands) {
        self.model = model
        self.menuBarCommands = menuBarCommands
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
        if let run = runs[command.id], run.isRunning {
            return
        }
        let session = ExtensionSession(command: command, launchType: "background")
        session.onMessage = { [weak self, weak session] message in
            guard let self, let session else { return }
            switch message["type"] as? String {
            case "exit", "close", "crashed":
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
        runs[command.id] = session
        session.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self, weak session] in
            guard let self, let session else { return }
            if session.isRunning {
                session.forceStop()
            }
            if runs[command.id] === session {
                runs.removeValue(forKey: command.id)
            }
        }
    }
}
