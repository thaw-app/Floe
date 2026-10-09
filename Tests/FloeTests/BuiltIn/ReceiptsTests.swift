//
//  ReceiptsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct ReceiptsTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-receipts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func model(in folder: URL) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-receipts-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        return model
    }

    @Test func aFileMovedToTheTrashIsPutBackWhereItWas() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.txt")
        try Data("kept".utf8).write(to: file)

        let receipt = try ReceiptStore.trash(file)
        defer { receipt.trashed.map { try? FileManager.default.removeItem(atPath: $0) } }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(receipt.kind == .trash)
        #expect(receipt.subject == "notes.txt")
        #expect(receipt.title == "Moved notes.txt to the Trash")
        #expect(receipt.canUndo)

        #expect(ReceiptUndo.undo(receipt) == .putBack)
        #expect(try String(contentsOf: file, encoding: .utf8) == "kept")
    }

    @Test func somethingNewerAtTheOldPlaceIsNotWrittenOver() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.txt")
        try Data("old".utf8).write(to: file)
        let receipt = try ReceiptStore.trash(file)
        defer { receipt.trashed.map { try? FileManager.default.removeItem(atPath: $0) } }
        try Data("newer".utf8).write(to: file)

        #expect(ReceiptUndo.undo(receipt) == .inTheWay)
        #expect(try String(contentsOf: file, encoding: .utf8) == "newer", "the newer file is left as it is")
        #expect(try FileManager.default.fileExists(atPath: #require(receipt.trashed)), "and the old one stays in the Trash")
        #expect(ReceiptUndo.message(for: .inTheWay, subject: "notes.txt") == "Something else is where notes.txt was, so it stays in the Trash")
    }

    @Test func whatLeftTheTrashOrNeverWentThereCannotBePutBack() {
        let gone = Receipt(date: Date(), kind: .trash, subject: "a.txt", detail: "", original: "/tmp/floe-a-\(UUID().uuidString)", trashed: "/tmp/floe-no-such-\(UUID().uuidString)")
        #expect(ReceiptUndo.undo(gone) == .gone)
        let command = Receipt(date: Date(), kind: .command, subject: "pkill -f x", detail: "Done")
        #expect(!command.canUndo)
        #expect(ReceiptUndo.undo(command) == .notUndoable)
        #expect(command.text.contains("This cannot be undone."))
        var undone = gone
        undone.undone = Date()
        #expect(!undone.canUndo, "once is enough")
    }

    @Test func receiptsAreKeptNewestFirstUpToTheLimitAndForgotten() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        #expect(store.all.isEmpty)
        for number in 0 ..< ReceiptStore.limit + 5 {
            store.add(Receipt(date: Date(timeIntervalSince1970: Double(number)), kind: .command, subject: "echo \(number)", detail: ""))
        }
        #expect(store.all.count == ReceiptStore.limit)
        #expect(store.all.first?.subject == "echo \(ReceiptStore.limit + 4)")
        let first = try #require(store.all.first)
        store.markUndone(first.id, at: Date(timeIntervalSince1970: 9))
        #expect(ReceiptStore(file: folder.appendingPathComponent("Receipts.json")).all.first?.undone == Date(timeIntervalSince1970: 9), "another process reads the same file")
        store.forget()
        #expect(store.all.isEmpty)
    }

    @Test func aReceiptSaysWhatWhenAndWhetherItCanBePutBack() {
        let now = Date(timeIntervalSince1970: 10000)
        let trashed = Receipt(date: now.addingTimeInterval(-7200), kind: .trash, subject: "a.txt", detail: "~/a.txt", original: "/a", trashed: "/b")
        #expect(trashed.label(now: now).hasSuffix(" · can be put back"))
        var back = trashed
        back.undone = now
        #expect(back.label(now: now).hasSuffix(" · put back"))
        #expect(!Receipt(date: now, kind: .process, subject: "Thaw", detail: "").label(now: now).contains("·"))
        let kinds: [Receipt.Kind] = [.command, .trash, .process, .extensionRemoved, .reminder, .event, .note, .noteLine, .checkpoint, .timer]
        #expect(kinds.map { Receipt(date: now, kind: $0, subject: "X", detail: "").title } == [
            "Ran X", "Moved X to the Trash", "Quit X", "Removed the extension X", "Added the reminder X", "Added the event X",
            "Wrote the note X", "Added a line to the note X", "Saved the checkpoint X", "Started the timer X",
        ])
    }

    @Test func theWordListsThemAndTextNarrowsThem() {
        var scope = ReceiptsSearchScope()
        let ran = Receipt(date: Date(), kind: .command, subject: "pkill -f debug/ThawNotch", detail: "Done")
        let moved = Receipt(date: Date(), kind: .trash, subject: "notes.txt", detail: "~/Documents/notes.txt", original: "/a", trashed: "/b")
        scope.receipts = { [ran, moved] }
        #expect(scope.text(in: SearchContext(query: "receipts")) == "")
        #expect(scope.text(in: SearchContext(query: "receipts thaw")) == "thaw")
        #expect(scope.text(in: SearchContext(query: "receipt")) == nil)
        #expect(scope.results(for: "", context: SearchContext(query: "receipts")).map(\.title) == [ran.title, moved.title])
        #expect(scope.results(for: "documents", context: SearchContext(query: "receipts documents")).map(\.title) == [moved.title], "what a receipt holds is searched too")
        #expect(RootItem.receipt(moved).kind == "Receipt")
        #expect(RootItem.receipt(moved).isScopeResult)
    }

    @Test func aCommandAndAProcessLeaveReceiptsUnlessSwitchedOff() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        model.shell.run = { _, _ in ("first line", "all of it") }
        model.shell.endProcess = { _, _ in true }
        model.shell.showOutput = { _, _ in }

        model.runShellCommand("uptime", terminal: nil)
        for _ in 0 ..< 100 where model.receipts.all.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        model.end(RunningProcess(pid: 400, path: "/x/ThawNotch", memory: 0), force: false)
        #expect(model.receipts.all.map(\.title) == ["Quit ThawNotch", "Ran uptime"])
        #expect(model.receipts.all.last?.detail == "first line")

        model.runShellCommand("man ls", terminal: nil)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(model.receipts.all.count == 2, "reading a manual changed nothing")

        model.settings.keepsReceipts = false
        model.end(RunningProcess(pid: 401, path: "/x/Other", memory: 0), force: false)
        #expect(model.receipts.all.count == 2)
    }

    @Test func returnOnAReceiptPutsBackWhatCanBeAndShowsTheRest() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var shown: [String] = []
        model.shell.showOutput = { title, _ in shown.append(title) }
        let file = folder.appendingPathComponent("draft.md")
        try Data("x".utf8).write(to: file)
        let receipt = try ReceiptStore.trash(file)
        defer { receipt.trashed.map { try? FileManager.default.removeItem(atPath: $0) } }
        model.record(receipt)
        let row = RootItem.receipt(receipt)

        #expect(model.primaryActionTitle(for: row) == "Put Back")
        #expect(model.rootActions(for: row).map { $0?.title ?? "-" } == ["Put Back", "Show Details", "-", "Copy"])
        model.activate(row)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(said == ["Put draft.md back"])
        let after = try #require(model.receipts.all.first)
        #expect(after.undone != nil)

        let done = RootItem.receipt(after)
        #expect(model.primaryActionTitle(for: done) == "Show Details")
        model.activate(done)
        #expect(shown == [after.title])
        let ran = RootItem.receipt(Receipt(date: Date(), kind: .command, subject: "uptime", detail: "ok"))
        #expect(model.rootActions(for: ran).map { $0?.title ?? "-" } == ["Show Details", "Run Again", "-", "Copy"])
    }
}
