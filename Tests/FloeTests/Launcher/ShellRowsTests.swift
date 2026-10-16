//
//  ShellRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// The shell as a row owner, with a host that records what it was asked: no launcher.
@MainActor
struct ShellRowsTests {
    private final class Asked {
        var queries: [String] = []
        var left = 0
    }

    private let asked = Asked()

    private func rows() throws -> ShellRows {
        let scratch = ScratchDefaults()
        let rows = ShellRows(settings: AppSettings(defaults: scratch.defaults, savesAfterEdits: false))
        let asked = asked
        rows.host = ShellRows.Host(leave: { asked.left += 1 }, setQuery: { asked.queries.append($0) })
        rows.environment.run = { _, _ in ("", "") }
        return rows
    }

    @Test func aRowThatIsNotTheShellsIsLeftToOthers() throws {
        let rows = try rows()
        let other = RootItem.emojiSearch
        #expect(rows.returnTitle(for: other) == nil)
        #expect(rows.actions(for: other) == nil)
        #expect(!rows.open(other, flags: []))
        #expect(!rows.handleKey(48, flags: [], on: other))
    }

    @Test func tabPutsASuggestionInTheSearchButNotWhatWasTyped() throws {
        let rows = try rows()
        let earlier = RootItem.shell(ShellRow(text: "git pull", origin: .history), terminal: nil)
        let typed = RootItem.shell(ShellRow(text: "ls", origin: .typed), terminal: nil)
        #expect(rows.handleKey(48, flags: [], on: earlier))
        #expect(!rows.handleKey(48, flags: [], on: typed))
        #expect(!rows.handleKey(48, flags: .shift, on: earlier))
        #expect(asked.queries.count == 1)
        #expect(asked.queries.first?.hasSuffix(" git pull") == true)
    }

    @Test func returnOnACommandLeavesTheLauncherAndItsMenuOffersMore() throws {
        let rows = try rows()
        let typed = RootItem.shell(ShellRow(text: "ls", origin: .typed), terminal: nil)
        #expect(rows.returnTitle(for: typed) != nil)
        #expect(rows.actions(for: typed)?.isEmpty == false)
        #expect(rows.open(typed, flags: []))
        #expect(asked.left == 1)
    }
}
