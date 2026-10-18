//
//  BrewRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// Homebrew packages as a row owner, with a terminal that only writes down the command.
@MainActor
final class BrewRowsTests {
    private let board = NSPasteboard.withUniqueName()
    private let asked = CallLog()
    private let rows = BrewRows()

    init() {
        let asked = asked
        rows.pasteboard = board
        rows.host = RowHost(showHUD: { asked.note("hud: \($0)") })
        rows.runInTerminal = { asked.note("run: \($0)") }
    }

    isolated deinit {
        board.releaseGlobally()
    }

    @Test func returnRunsThePrimaryCommandInTheTerminal() {
        let package = BrewPackage(name: "ripgrep", isCask: false, isInstalled: false)
        #expect(rows.returnTitle(for: .brew(package)) == "Install in Terminal")
        #expect(rows.open(.brew(package), flags: []))
        #expect(asked.all == ["run: \(Homebrew.command(Homebrew.primaryVerb(for: package), package))"])
    }

    @Test func anInstalledPackagesMenuUninstallsAndEveryPackageCopiesItsName() throws {
        let installed = BrewPackage(name: "ripgrep", isCask: false, isInstalled: true)
        let actions = try #require(rows.actions(for: .brew(installed)))
        #expect(actions.compactMap { $0?.title } == ["Uninstall in Terminal", "Copy Name"])
        for action in actions {
            action?.run()
        }
        #expect(asked.all == ["run: \(Homebrew.command(.uninstall, installed))", "hud: Copied ripgrep"])
        #expect(board.string(forType: .string) == "ripgrep")

        let missing = BrewPackage(name: "wget", isCask: false, isInstalled: false)
        #expect(rows.actions(for: .brew(missing))?.compactMap { $0?.title } == ["Copy Name"])
    }

    @Test func aRowThatIsNotAPackageIsLeftToOthers() {
        #expect(!rows.open(.emojiSearch, flags: []))
        #expect(rows.actions(for: .emojiSearch) == nil)
        #expect(rows.returnTitle(for: .emojiSearch) == nil)
        #expect(asked.all.isEmpty)
    }
}
