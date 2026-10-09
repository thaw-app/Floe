//
//  Model+Music.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What the music commands reach the players through. Tests replace all of it, so none runs a script or shows an alert.
struct MusicEnvironment {
    /// Whether a player is open, read without scripting it.
    var isRunning: (MusicPlayer) -> Bool = { MusicPlayer.isRunning($0) }
    /// Runs a script and waits for it. Called off the main thread.
    var run: AppleScriptRunner = AppleScript.run
    /// Shows where Automation is allowed, after macOS refused a script. Takes the player's name.
    var askForAutomation: (String) -> Void = { SystemCommand.askForAutomation(toControl: $0) }
}

/// Music, as the launcher controls it.
extension LauncherModel {
    /// Tells the open player what to do and says what came of it. The task is for a test to wait on.
    @discardableResult
    func controlMusic(_ command: MusicCommand) -> Task<Void, Never> {
        switch MusicControls.plan(command, isRunning: music.isRunning) {
        case let .say(line):
            showHUD(line)
            return Task { /* nothing to run */ }
        case let .run(source, player):
            return Task { [weak self, music] in
                let outcome = await MusicControls.run(source, with: music.run)
                if outcome == .refused {
                    music.askForAutomation(player.name)
                } else if let line = MusicControls.line(for: command, outcome: outcome, player: player) {
                    self?.showHUD(line)
                }
            }
        }
    }
}
