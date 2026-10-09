//
//  MusicControls.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// An app that plays music and takes its orders through AppleScript.
nonisolated struct MusicPlayer: Equatable, Sendable {
    let name: String
    let bundleID: String

    static let spotify = MusicPlayer(name: "Spotify", bundleID: "com.spotify.client")
    static let music = MusicPlayer(name: "Music", bundleID: "com.apple.Music")
    /// Spotify first: with both open, it is the one that was opened to listen to.
    static let all = [spotify, music]

    /// Read without scripting, so asking never launches the app or needs a permission.
    static func isRunning(_ player: MusicPlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }
}

/// What the music commands ask of a player.
nonisolated enum MusicCommand: CaseIterable, Sendable {
    case playPause, nextTrack, previousTrack, nowPlaying
}

extension SystemCommand {
    /// The music command a system command stands for. Nil for every other one.
    nonisolated var music: MusicCommand? {
        switch self {
        case .playPause: .playPause
        case .nextTrack: .nextTrack
        case .previousTrack: .previousTrack
        case .nowPlaying: .nowPlaying
        default: nil
        }
    }
}

/// The scripts that control a player, and the reading of what Now Playing answers.
/// Music and Spotify share these terms in their scripting definitions.
nonisolated enum MusicScripts {
    static let fieldSeparator = "\u{1F}"

    /// What starts Music playing when no player is open.
    static let startMusic = "tell application id \(AppleScript.literal(MusicPlayer.music.bundleID)) to play"

    static func script(_ command: MusicCommand, for player: MusicPlayer) -> String {
        let app = "application id \(AppleScript.literal(player.bundleID))"
        switch command {
        case .playPause: return "tell \(app) to playpause"
        case .nextTrack: return "tell \(app) to next track"
        case .previousTrack: return "tell \(app) to previous track"
        case .nowPlaying: return """
            tell \(app)
                if player state is stopped then return ""
                set floeTrack to current track
                return my floeText(name of floeTrack) & character id 31 & my floeText(artist of floeTrack)
            end tell

            on floeText(floeValue)
                if floeValue is missing value then return ""
                return floeValue as text
            end floeText
            """
        }
    }

    /// The track and its artist, as Now Playing answered them. Nil when nothing is playing.
    static func track(in output: String) -> (name: String, artist: String)? {
        let fields = output.components(separatedBy: fieldSeparator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name = fields.first, !name.isEmpty else { return nil }
        return (name, fields.count > 1 ? fields[1] : "")
    }
}

/// Which player a command goes to, what it is told, and what the HUD says of the answer.
nonisolated enum MusicControls {
    /// A script for a player, or with nothing to run, the line that says why.
    enum Plan: Equatable {
        case run(String, MusicPlayer)
        case say(String)
    }

    /// The first player that is open. Nil when neither is.
    static func target(isRunning: (MusicPlayer) -> Bool) -> MusicPlayer? {
        MusicPlayer.all.first(where: isRunning)
    }

    /// With no player open, Play/Pause starts Music and the other commands have nothing to act on.
    static func plan(_ command: MusicCommand, isRunning: (MusicPlayer) -> Bool) -> Plan {
        if let player = target(isRunning: isRunning) {
            return .run(MusicScripts.script(command, for: player), player)
        }
        guard command == .playPause else {
            return .say(String(localized: "Neither Spotify nor Music is open", bundle: .floe, comment: "Spotify and Music are the names of two apps."))
        }
        return .run(MusicScripts.startMusic, .music)
    }

    /// What the HUD says once the player answered. Nil when the music says it: it stopped, or the track changed.
    static func line(for command: MusicCommand, outcome: AppleScriptOutcome, player: MusicPlayer) -> String? {
        switch outcome {
        case .refused:
            return nil
        case .failed:
            return String(localized: "\(player.name) did not answer", bundle: .floe, comment: "The placeholder is the name of a music app, Spotify or Music.")
        case let .text(output):
            guard command == .nowPlaying else { return nil }
            guard let track = MusicScripts.track(in: output) else {
                return String(localized: "Nothing is playing in \(player.name)", bundle: .floe, comment: "The placeholder is the name of a music app, Spotify or Music.")
            }
            return track.artist.isEmpty ? track.name : String(localized: "\(track.name) · \(track.artist)", bundle: .floe, comment: "The track that is playing. The first placeholder is its name, the second is the artist.")
        }
    }

    /// Runs a script off the main thread and answers with how it ended.
    @concurrent
    static func run(_ source: String, with runner: AppleScriptRunner) async -> AppleScriptOutcome {
        runner(source)
    }
}
