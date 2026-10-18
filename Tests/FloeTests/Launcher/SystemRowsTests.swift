//
//  SystemRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// System commands and SSH hosts as a row owner, with music and connections that only write down what was asked.
@MainActor
struct SystemRowsTests {
    private let asked = CallLog()
    private let rows = SystemRows()

    init() {
        let asked = asked
        rows.host = RowHost(showHUD: { asked.note("hud: \($0)") }, leave: { asked.note("leave") })
        rows.controlMusic = { asked.note("music: \($0)") }
        rows.sshConnector = SSHConnector(
            bundleIdentifier: { _ in nil },
            takesSSHLinks: { _ in false },
            systemTerminal: { nil },
            open: { _ in asked.note("open") },
            runScript: { _ in
                asked.note("script")
                return .text("")
            }
        )
    }

    @Test func aMusicCommandLeavesTheLauncherAndControlsTheMusic() {
        #expect(rows.open(.system(.playPause), flags: []))
        #expect(rows.open(.system(.nextTrack), flags: []))
        #expect(asked.all == ["leave", "music: \(MusicCommand.playPause)", "leave", "music: \(MusicCommand.nextTrack)"])
    }

    @Test func connectingToAHostWithNoTerminalSaysToChooseOne() async {
        let host = SSHHost(alias: "box")
        #expect(rows.returnTitle(for: .sshHost(host, terminal: nil)) == "Connect")
        #expect(rows.open(.sshHost(host, terminal: nil), flags: []))
        for _ in 0 ..< 1000 where asked.all.count < 2 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(asked.all == ["leave", "hud: \(SSHConnection.noTerminalNotice)"])
    }

    @Test func aHostsMenuOffersItsCopies() {
        let host = SSHHost(alias: "box")
        #expect(rows.actions(for: .sshHost(host, terminal: nil))?.compactMap { $0?.title } == ["Copy Host Name", "Copy SSH Command"])
    }

    @Test func aRowThatIsNotTheSystemsIsLeftToOthers() {
        #expect(!rows.open(.emojiSearch, flags: []))
        #expect(rows.returnTitle(for: .system(.playPause)) == nil)
        #expect(rows.actions(for: .system(.playPause)) == nil)
        #expect(asked.all.isEmpty)
    }
}
