//
//  ShellRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// The shell as a row owner, with a host and an environment that record what they were asked: no launcher, no shell.
@MainActor
struct ShellRowsTests {
    private final class Asked {
        var queries: [String] = []
        var left = 0
        var hidden = 0
        var huds: [String] = []
        var receipts: [Receipt] = []
        var outputs: [String] = []
        var handedToTerminal: [String] = []
        var copied: [String] = []
        var revealed: [URL] = []
        var automation: [String] = []
        var saved: [String] = []
        var scriptsChanged = 0
        var ended: [Bool] = []
    }

    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "no"
        }
    }

    private let asked = Asked()

    private func rows() -> ShellRows {
        let scratch = ScratchDefaults()
        let rows = ShellRows(settings: AppSettings(defaults: scratch.defaults, savesAfterEdits: false))
        let asked = asked
        rows.host = ShellRows.Host(
            hidePanel: { asked.hidden += 1 }, showHUD: { asked.huds.append($0) }, leave: { asked.left += 1 },
            record: { asked.receipts.append($0) }, setQuery: { asked.queries.append($0) }, scriptsChanged: { asked.scriptsChanged += 1 }
        )
        return recording(rows)
    }

    /// The rows with an environment that records what it was asked instead of running anything.
    private func recording(_ rows: ShellRows) -> ShellRows {
        let asked = asked
        rows.environment.run = { command, folder in ("printed", "\(command) in \(folder?.path ?? "~")") }
        rows.environment.showOutput = { _, output in asked.outputs.append(output) }
        rows.environment.runInTerminal = { command, _ in asked.handedToTerminal.append(command) }
        rows.environment.copy = { asked.copied.append($0) }
        rows.environment.reveal = { asked.revealed.append($0) }
        rows.environment.askForAutomation = { asked.automation.append($0) }
        rows.environment.save = { command, title in asked.saved.append("\(title): \(command)") }
        rows.environment.endProcess = { _, force in
            asked.ended.append(force)
            return true
        }
        rows.environment.finderFolder = { URL(fileURLWithPath: "/tmp/front") }
        return rows
    }

    /// Waits for work the rows hand to a task.
    private func settle(until done: () -> Bool) async {
        for _ in 0 ..< 200 where !done() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aRowThatIsNotTheShellsIsLeftToOthers() {
        let rows = rows()
        let other = RootItem.emojiSearch
        #expect(rows.returnTitle(for: other) == nil)
        #expect(rows.actions(for: other) == nil)
        #expect(!rows.open(other, flags: []))
        #expect(!rows.handleKey(48, flags: [], on: other))
    }

    @Test func tabPutsASuggestionInTheSearchButNotWhatWasTyped() {
        let rows = rows()
        let earlier = RootItem.shell(ShellRow(text: "git pull", origin: .history), terminal: nil)
        let typed = RootItem.shell(ShellRow(text: "ls", origin: .typed), terminal: nil)
        #expect(rows.handleKey(48, flags: [], on: earlier))
        #expect(!rows.handleKey(48, flags: [], on: typed))
        #expect(!rows.handleKey(48, flags: .shift, on: earlier))
        #expect(asked.queries.count == 1)
        #expect(asked.queries.first?.hasSuffix(" git pull") == true)
    }

    @Test func returnOnACommandLeavesTheLauncherAndShowsItsFirstLine() async {
        let rows = rows()
        let typed = RootItem.shell(ShellRow(text: "ls", origin: .typed), terminal: nil)
        #expect(rows.returnTitle(for: typed) != nil)
        #expect(rows.open(typed, flags: []))
        #expect(asked.left == 1)
        await settle { !asked.huds.isEmpty }
        #expect(asked.huds == ["printed"])
        #expect(asked.receipts.map(\.subject) == ["ls"])
    }

    @Test func aCommandThatAsksForAPasswordIsHandedToATerminal() {
        let rows = rows()
        rows.runShellCommand("sudo ls", terminal: nil)
        #expect(asked.handedToTerminal == ["sudo ls"])
        #expect(asked.receipts.map(\.subject) == ["sudo ls"])
        rows.environment.runInTerminal = { _, _ in throw Failure() }
        rows.runShellCommand("sudo ls", terminal: nil)
        #expect(asked.huds == ["no"])
    }

    @Test func commandOpensATerminalAndOptionShowsTheWholeOutput() async {
        let rows = rows()
        #expect(rows.open(.shell(ShellRow(text: "top", origin: .typed), terminal: nil), flags: .command))
        #expect(asked.handedToTerminal == ["top"])
        rows.runShellCommand("ls", terminal: nil, with: .option)
        await settle { !asked.outputs.isEmpty }
        #expect(asked.outputs == ["ls in ~"])
        rows.runShellCommand("pwd", terminal: nil, with: .control)
        await settle { !asked.huds.isEmpty }
        #expect(asked.huds == ["printed"])
    }

    @Test func returnWithAKeyHeldReachesACommandInTheSearch() async {
        // A command row is one of the search's own rows, opened apart from the others, and the keys held still reach it.
        let model = LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [], commands: []))
        _ = recording(model.features.shell)
        let top = RootItem.shell(ShellRow(text: "top", origin: .typed), terminal: nil)
        #expect(top.isScopeResult)
        model.activate(top, flags: .command)
        #expect(asked.handedToTerminal == ["top"])
        model.activate(.shell(ShellRow(text: "ls", origin: .typed), terminal: nil), flags: .option)
        await settle { !asked.outputs.isEmpty }
        #expect(asked.outputs == ["ls in ~"], "Option shows the whole output, as the Output hint says")
    }

    @Test func shiftRunsTheCommandInFindersFolder() async {
        let rows = rows()
        rows.runShellCommand("ls", terminal: nil, with: .shift)
        await settle { !asked.outputs.isEmpty }
        #expect(asked.outputs == ["ls in /tmp/front"])
    }

    @Test func finderThatMayNotBeControlledAsksForPermissionAndAnyOtherFailureSaysWhy() async {
        let rows = rows()
        rows.environment.finderFolder = { throw SelectionError.automationRefused }
        rows.runInFinderFolder("ls", terminal: nil)
        await settle { !asked.automation.isEmpty }
        #expect(asked.automation == ["Finder"])
        rows.environment.finderFolder = { throw Failure() }
        rows.runInFinderFolder("ls", terminal: nil)
        await settle { !asked.huds.isEmpty }
        #expect(asked.huds == ["no"])
    }

    @Test func copyingTheOutputPutsEverythingPrintedOnTheClipboard() async {
        let rows = rows()
        rows.copyOutput(of: "date")
        await settle { !asked.huds.isEmpty }
        #expect(asked.left == 1)
        #expect(asked.copied == ["date in ~"])
        #expect(asked.receipts.map(\.subject) == ["date"])
    }

    @Test func aSavedCommandTakesTheNameGivenWithoutItsSpaces() {
        let rows = rows()
        rows.environment.nameForSaving = { _ in "  Deploy \n" }
        rows.saveShellCommand("make deploy")
        #expect(asked.hidden == 1)
        #expect(asked.saved == ["Deploy: make deploy"])
        #expect(asked.scriptsChanged == 1)
        #expect(asked.huds.count == 1)
    }

    @Test func aCommandIsNotSavedWithoutANameAndAFailedSaveSaysWhy() {
        let rows = rows()
        rows.environment.nameForSaving = { _ in nil }
        rows.saveShellCommand("make deploy")
        rows.environment.nameForSaving = { _ in "   " }
        rows.saveShellCommand("make deploy")
        #expect(asked.saved.isEmpty)
        #expect(asked.huds.isEmpty)
        rows.environment.nameForSaving = { _ in "Deploy" }
        rows.environment.save = { _, _ in throw Failure() }
        rows.saveShellCommand("make deploy")
        #expect(asked.scriptsChanged == 0)
        #expect(asked.huds == ["no"])
    }

    @Test func aCommandsMenuRunsItEveryWayAndReadsItsProgramsManual() async throws {
        let rows = rows()
        rows.environment.hasProgram = { _ in true }
        let actions = try #require(rows.actions(for: .shell(ShellRow(text: "ls -la", origin: .typed), terminal: nil)))
        let run = { (symbol: String) in actions.first { $0?.symbol == symbol }??.run() }
        run("book")
        run("list.bullet.rectangle")
        run("text.alignleft")
        await settle { asked.outputs.count == 3 }
        #expect(asked.outputs.contains { $0.contains("man -P cat ls") })
        #expect(asked.outputs.contains("tldr ls in ~"))
        #expect(asked.outputs.contains("ls -la in ~"))
        run("terminal")
        run("doc.on.doc")
        #expect(asked.handedToTerminal == ["ls -la"])
        #expect(asked.copied == ["ls -la"])
        run("doc.on.clipboard")
        run("folder")
        await settle { asked.copied.count == 2 && asked.outputs.count == 4 }
        #expect(asked.copied.last == "ls -la in ~")
        #expect(asked.outputs.last == "ls -la in /tmp/front")
        rows.environment.nameForSaving = { _ in "List" }
        run("square.and.arrow.down")
        #expect(asked.saved == ["List: ls -la"])
    }

    @Test func aProcessesMenuForceQuitsOnlyWhenConfirmedAndShowsOrCopiesIt() throws {
        let rows = rows()
        let process = RunningProcess(pid: 42, path: "/Applications/Mail.app/Contents/MacOS/Mail", memory: 1024)
        let actions = try #require(rows.actions(for: .process(process)))
        let run = { (symbol: String) in actions.first { $0?.symbol == symbol }??.run() }
        rows.environment.confirmsForceQuit = { _, _ in }
        run("xmark.octagon")
        #expect(asked.ended.isEmpty)
        rows.environment.confirmsForceQuit = { _, goAhead in goAhead() }
        run("xmark.octagon")
        #expect(asked.ended == [true])
        run("folder")
        #expect(asked.revealed == [URL(fileURLWithPath: process.path)])
        #expect(asked.hidden == 1)
        run("number")
        #expect(asked.copied == ["42"])
    }
}
