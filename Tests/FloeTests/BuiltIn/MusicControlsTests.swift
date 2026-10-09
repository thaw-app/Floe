//
//  MusicControlsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// What stands in for the players: which are open, the scripts they were sent, and what they answer.
private final nonisolated class Stand: Sendable {
    struct State {
        var open: [String] = []
        var answer = AppleScriptOutcome.text("")
        var scripts: [String] = []
        var ranOnMain: Bool?
    }

    let state = Mutex(State())

    var runner: AppleScriptRunner {
        { [self] source in
            state.withLock {
                $0.scripts.append(source)
                $0.ranOnMain = Thread.isMainThread
                return $0.answer
            }
        }
    }

    var scripts: [String] {
        state.withLock { $0.scripts }
    }

    func isRunning(_ player: MusicPlayer) -> Bool {
        state.withLock { $0.open.contains(player.bundleID) }
    }
}

@MainActor
struct MusicControlsTests {
    private static nonisolated let spotify = "com.spotify.client"
    private static nonisolated let appleMusic = "com.apple.Music"

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-music-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A model whose players are the stand-in. The lists it fills are the HUD's lines and the apps Automation was asked for.
    private func model(in folder: URL, stand: Stand, said: @escaping (String) -> Void, asked: @escaping (String) -> Void = { _ in }) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-music-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.music = MusicEnvironment(isRunning: { stand.isRunning($0) }, run: stand.runner, askForAutomation: asked)
        model.showHUD = said
        return model
    }

    // MARK: The player

    @Test func theCommandGoesToSpotifyWhenBothAreOpen() {
        #expect(MusicControls.target { _ in true } == .spotify)
        #expect(MusicControls.target { $0 == .music } == .music)
        #expect(MusicControls.target { $0 == .spotify } == .spotify)
        #expect(MusicControls.target { _ in false } == nil)
        #expect(MusicPlayer.all.map(\.bundleID) == [Self.spotify, Self.appleMusic])
        #expect(MusicPlayer.all.map(\.name) == ["Spotify", "Music"])
    }

    @Test func withNoPlayerOpenPlayStartsMusicAndTheRestSayThereIsNone() {
        #expect(MusicControls.plan(.playPause) { _ in false } == .run(#"tell application id "com.apple.Music" to play"#, .music))
        for command in [MusicCommand.nextTrack, .previousTrack, .nowPlaying] {
            #expect(MusicControls.plan(command) { _ in false } == .say("Neither Spotify nor Music is open"))
        }
        #expect(MusicControls.plan(.nextTrack) { $0 == .music } == .run(#"tell application id "com.apple.Music" to next track"#, .music))
        #expect(MusicControls.plan(.playPause) { _ in true } == .run(#"tell application id "com.spotify.client" to playpause"#, .spotify))
    }

    // MARK: The scripts

    @Test(arguments: [MusicPlayer.spotify, .music])
    func theScriptsNameThePlayerByItsIdentifier(player: MusicPlayer) {
        let app = #"application id "\#(player.bundleID)""#
        #expect(MusicScripts.script(.playPause, for: player) == "tell \(app) to playpause")
        #expect(MusicScripts.script(.nextTrack, for: player) == "tell \(app) to next track")
        #expect(MusicScripts.script(.previousTrack, for: player) == "tell \(app) to previous track")

        let playing = MusicScripts.script(.nowPlaying, for: player)
        #expect(playing.hasPrefix("tell \(app)\n"))
        #expect(playing.contains(#"if player state is stopped then return """#), "a stopped player has no current track to ask for")
        #expect(playing.contains("my floeText(name of floeTrack) & character id 31 & my floeText(artist of floeTrack)"))
        #expect(playing.contains("if floeValue is missing value then return \"\""))
        #expect(!playing.contains("activate"), "asking what plays does not bring the player forward")
    }

    @Test func nowPlayingIsReadAsATrackAndItsArtist() {
        let sep = MusicScripts.fieldSeparator
        #expect(sep == "\u{1F}")
        #expect(MusicScripts.track(in: "So What\(sep)Miles Davis").map { [$0.name, $0.artist] } == ["So What", "Miles Davis"])
        #expect(MusicScripts.track(in: "Episode 12\(sep)").map { [$0.name, $0.artist] } == ["Episode 12", ""])
        #expect(MusicScripts.track(in: " So What \(sep) Miles Davis \n").map { [$0.name, $0.artist] } == ["So What", "Miles Davis"])
        #expect(MusicScripts.track(in: "") == nil)
        #expect(MusicScripts.track(in: "\(sep)Miles Davis") == nil)
    }

    @Test func theHUDSaysWhatPlaysAndStaysQuietWhenTheMusicSaysIt() {
        let sep = MusicScripts.fieldSeparator
        #expect(MusicControls.line(for: .nowPlaying, outcome: .text("So What\(sep)Miles Davis"), player: .music) == "So What · Miles Davis")
        #expect(MusicControls.line(for: .nowPlaying, outcome: .text("Episode 12\(sep)"), player: .spotify) == "Episode 12")
        #expect(MusicControls.line(for: .nowPlaying, outcome: .text(""), player: .spotify) == "Nothing is playing in Spotify")
        for command in [MusicCommand.playPause, .nextTrack, .previousTrack] {
            #expect(MusicControls.line(for: command, outcome: .text(""), player: .music) == nil)
            #expect(MusicControls.line(for: command, outcome: .failed, player: .music) == "Music did not answer")
        }
        #expect(MusicControls.line(for: .nowPlaying, outcome: .failed, player: .spotify) == "Spotify did not answer")
        #expect(MusicControls.line(for: .nowPlaying, outcome: .refused, player: .spotify) == nil, "a refusal is answered with the question, not a line")
    }

    // MARK: The commands

    @Test func theFourCommandsAreSystemCommands() {
        let music = SystemCommand.allCases.filter { $0.music != nil }
        #expect(music == [.playPause, .nextTrack, .previousTrack, .nowPlaying])
        #expect(music.compactMap(\.music) == MusicCommand.allCases)
        #expect(music.map(\.title) == ["Play/Pause", "Next Track", "Previous Track", "Now Playing"])
        #expect(music.map(\.rawValue) == ["playPause", "nextTrack", "previousTrack", "nowPlaying"])
        for command in music {
            #expect(command.confirmation == nil)
            #expect(command.flip == nil)
            #expect(RootItem.system(command).settingsKey == "system:\(command.rawValue)", "it has the key every system command has")
            #expect(LauncherModel.keepsItsPlace(.system(command)))
        }
        #expect(SystemCommand.lockScreen.music == nil)
    }

    @Test(arguments: [
        ("pause", "system:playPause"), ("play", "system:playPause"), ("resume", "system:playPause"),
        ("next song", "system:nextTrack"), ("skip", "system:nextTrack"), ("next track", "system:nextTrack"),
        ("previous", "system:previousTrack"), ("previous song", "system:previousTrack"),
        ("what's playing", "system:nowPlaying"), ("now playing", "system:nowPlaying"), ("current song", "system:nowPlaying"),
    ])
    func aMusicCommandIsFoundByWhatPeopleCallIt(query: String, id: String) {
        let results = Ranking.search(
            SystemCommand.allCases.map(RootItem.system), query: query, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }
        )
        #expect(results.first?.item.id == id)
    }

    // MARK: Return

    @Test func returnSendsTheScriptOffTheMainThreadAndClosesThePanel() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.state.withLock { $0.open = [Self.appleMusic] }
        var said: [String] = []
        let model = model(in: folder, stand: stand) { said.append($0) }
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "next song"
        let row = try #require(model.results.first?.item)
        #expect(row.id == "system:nextTrack")
        #expect(row.rowLabel == "System")
        model.activate(row)
        #expect(hidden == 1)
        for _ in 0 ..< 200 where stand.scripts.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(stand.scripts == [#"tell application id "com.apple.Music" to next track"#])
        #expect(stand.state.withLock { $0.ranOnMain } == false)

        stand.state.withLock { $0.open = [Self.appleMusic, Self.spotify] }
        await model.controlMusic(.playPause).value
        await model.controlMusic(.previousTrack).value
        #expect(stand.scripts.dropFirst() == [#"tell application id "com.spotify.client" to playpause"#, #"tell application id "com.spotify.client" to previous track"#])
        #expect(said.isEmpty, "the music says it")
        #expect(model.receipts.all.isEmpty)
    }

    @Test func nowPlayingShowsTheTrackAndItsArtist() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.state.withLock {
            $0.open = [Self.spotify]
            $0.answer = .text("So What\(MusicScripts.fieldSeparator)Miles Davis")
        }
        var said: [String] = []
        let model = model(in: folder, stand: stand) { said.append($0) }
        await model.controlMusic(.nowPlaying).value
        #expect(said == ["So What · Miles Davis"])
        #expect(stand.scripts == [MusicScripts.script(.nowPlaying, for: .spotify)])

        stand.state.withLock { $0.answer = .text("") }
        await model.controlMusic(.nowPlaying).value
        #expect(said.last == "Nothing is playing in Spotify")
        stand.state.withLock { $0.answer = .failed }
        await model.controlMusic(.nextTrack).value
        #expect(said.last == "Spotify did not answer")
    }

    @Test func withNoPlayerOpenNothingIsScriptedButPlay() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        var said: [String] = []
        let model = model(in: folder, stand: stand) { said.append($0) }
        for command in [MusicCommand.nextTrack, .previousTrack, .nowPlaying] {
            await model.controlMusic(command).value
        }
        #expect(said == Array(repeating: "Neither Spotify nor Music is open", count: 3))
        #expect(stand.scripts.isEmpty)

        await model.controlMusic(.playPause).value
        #expect(stand.scripts == [#"tell application id "com.apple.Music" to play"#])
        #expect(said.count == 3)
    }

    @Test func aRefusedPermissionIsAnsweredWithWhereToAllowIt() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.state.withLock {
            $0.open = [Self.spotify]
            $0.answer = .refused
        }
        var said: [String] = []
        var asked: [String] = []
        let model = model(in: folder, stand: stand, said: { said.append($0) }, asked: { asked.append($0) })
        await model.controlMusic(.playPause).value
        #expect(asked == ["Spotify"])
        #expect(said.isEmpty)

        stand.state.withLock { $0.open = [] }
        await model.controlMusic(.playPause).value
        #expect(asked == ["Spotify", "Music"], "starting Music is scripting it too")
    }
}
