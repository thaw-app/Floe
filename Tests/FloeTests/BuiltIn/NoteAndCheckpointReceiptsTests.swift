//
//  NoteAndCheckpointReceiptsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct NoteAndCheckpointReceiptsTests {
    private struct Refused: Error {}

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-note-receipts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        return folder
    }

    /// A model whose stores are in the folder, whose notes go to the Notes folder inside it, and that reaches nothing else.
    private func model(in folder: URL) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-note-receipts-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.reminding = ReminderEnvironment(requestAccess: { false }, create: { _ in throw Refused() }, delete: { _ in throw Refused() }, lists: { [] })
        model.scheduling = EventEnvironment(requestAccess: { false }, create: { _ in throw Refused() }, delete: { _ in throw Refused() })
        model.checkpointing.finderItems = { [] }
        model.checkpointing.tabs = { [] }
        model.checkpointing.openFile = { _ in }
        model.checkpointing.confirmsDelete = { _ in false }
        model.shell.showOutput = { _, _ in }
        model.settings.notesApp = .folder
        model.settings.notesFolder = folder.appendingPathComponent("Notes").path
        return model
    }

    /// Takes out of the Trash whatever a test left there.
    private func emptyTrash(of model: LauncherModel) {
        for path in model.receipts.all.compactMap(\.trashed) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: A new note

    @Test func aNewNoteLeavesAReceiptThatMovesItToTheTrashAndThatCanBePutBack() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        defer { emptyTrash(of: model) }
        var said: [String] = []
        model.showHUD = { said.append($0) }
        let file = folder.appendingPathComponent("Notes/Buy milk.md")

        model.activate(.note(.new, text: "Buy milk"))
        #expect(said == ["Saved Buy milk"])
        let receipt = try #require(model.receipts.all.first)
        #expect(receipt.kind == .note)
        #expect(receipt.subject == "Buy milk")
        #expect(receipt.title == "Wrote the note Buy milk")
        #expect(receipt.original?.hasSuffix("/Notes/Buy milk.md") == true)
        #expect(receipt.size == 9)
        #expect(receipt.modified != nil)
        #expect(receipt.canUndo)
        #expect(receipt.label().hasSuffix(" · can be moved to the Trash"))
        let row = RootItem.receipt(receipt)
        #expect(model.primaryActionTitle(for: row) == "Move to Trash")
        #expect(model.rootActions(for: row).map { $0?.title ?? "-" } == ["Move to Trash", "Show Details", "-", "Copy"])

        model.activate(row)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(said.last == "Moved Buy milk to the Trash")
        let after = model.receipts.all
        #expect(after.map(\.kind) == [.trash, .note], "the move to the Trash has a receipt of its own")
        #expect(after.map(\.canUndo) == [true, false], "once is enough")
        #expect(after.last?.label().hasSuffix(" · moved to the Trash") == true)
        #expect(after.last?.text.contains("\nMoved to the Trash ") == true)

        try model.activate(.receipt(#require(after.first)))
        #expect(try String(contentsOf: file, encoding: .utf8) == "Buy milk\n", "and that one puts the note back")
    }

    @Test func aNoteChangedSinceFloeWroteItIsLeftWhereItIs() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        defer { emptyTrash(of: model) }
        var said: [String] = []
        model.showHUD = { said.append($0) }
        let file = folder.appendingPathComponent("Notes/Ideas.md")

        model.activate(.note(.new, text: "Ideas"))
        let receipt = try #require(model.receipts.all.first)
        try Data("Ideas\nand a second thought\n".utf8).write(to: file)
        model.undo(receipt)
        #expect(said.last == "Ideas was changed after Floe wrote it, so it stays where it is")
        #expect(try String(contentsOf: file, encoding: .utf8) == "Ideas\nand a second thought\n")
        #expect(model.receipts.all.map(\.kind) == [.note])

        try Data("Ideas\n".utf8).write(to: file)
        let later = try #require(receipt.modified).addingTimeInterval(90)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: file.path)
        #expect(ReceiptUndo.undo(receipt) == .changed, "the same size written at another time is a change too")
        #expect(FileManager.default.fileExists(atPath: file.path))

        try FileManager.default.removeItem(at: file)
        model.undo(receipt)
        #expect(said.last == "Ideas is no longer where Floe wrote it")
        #expect(model.receipts.all.first?.undone == nil)
    }

    @Test func aNoteAsFloeLeftItGoesThroughTheClosureItIsGiven() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Notes/Plan.md")
        try Data("Plan\n".utf8).write(to: file)
        let receipt = Receipt.note(file)
        var asked: [String] = []
        let moved = Receipt(date: Date(), kind: .trash, subject: "Plan.md", detail: "", original: file.path, trashed: "/in/the/trash")
        let outcome = ReceiptUndo.undo(receipt, trash: { url in
            asked.append(url.lastPathComponent)
            return moved
        })
        #expect(outcome == .trashed(moved))
        #expect(asked == ["Plan.md"])
        #expect(ReceiptUndo.undo(receipt, trash: { _ in throw CocoaError(.fileWriteNoPermission) }) == .failed(CocoaError(.fileWriteNoPermission).localizedDescription))
        #expect(FileManager.default.fileExists(atPath: file.path), "the stand-ins moved nothing")

        let read = try JSONDecoder().decode(Receipt.self, from: JSONEncoder().encode(receipt))
        #expect(ReceiptUndo.undo(read, trash: { _ in moved }) == .trashed(moved), "the size and date survive the receipts' file")
        var unstamped = receipt
        unstamped.modified = nil
        #expect(!unstamped.canUndo, "without what the file was, nothing says it is unchanged")
    }

    // MARK: A line in the day's note

    @Test func aLineAddedToTheDaysNoteLeavesAReceiptThatCannotBeUndone() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        let today = NoteFiles.todayName(now: Date())

        model.activate(.note(.today, text: "call the bank"))
        #expect(said == ["Added to today’s note"])
        let receipt = try #require(model.receipts.all.first)
        #expect(receipt.kind == .noteLine)
        #expect(receipt.title == "Added a line to the note \((today as NSString).deletingPathExtension)")
        #expect(receipt.detail.hasSuffix("/Notes/\(today)\ncall the bank"))
        #expect(!receipt.canUndo)
        #expect(!receipt.label().contains("·"))
        #expect(receipt.text.hasSuffix("\nThis cannot be undone: the note may have been edited since Floe added the line."))
        #expect(model.primaryActionTitle(for: .receipt(receipt)) == "Show Details")
        #expect(ReceiptUndo.undo(receipt) == .notUndoable)

        model.undo(receipt)
        #expect(said.last == "This cannot be undone.")
        #expect(try String(contentsOf: folder.appendingPathComponent("Notes/\(today)"), encoding: .utf8) == "call the bank\n")
    }

    // MARK: Where no receipt is left

    @Test func whatFloeCannotUndoOrDidNotWriteLeavesNoReceipt() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }

        model.settings.notesApp = .custom
        model.settings.notesURLTemplate = ""
        model.activate(.note(.new, text: "Buy milk"))
        #expect(said == ["Set a URL for your notes app in Settings"])
        #expect(model.receipts.all.isEmpty, "a note handed to another app is that app's")

        model.settings.notesApp = .folder
        model.settings.notesFolder = folder.appendingPathComponent("no-such-folder").path
        model.activate(.note(.new, text: "Buy milk"))
        #expect(said.last == "Choose a folder for your notes in Settings")
        #expect(model.receipts.all.isEmpty)

        model.settings.notesFolder = folder.appendingPathComponent("Notes").path
        model.settings.keepsReceipts = false
        model.activate(.note(.new, text: "Buy milk"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Notes/Buy milk.md").path))
        #expect(model.receipts.all.isEmpty, "receipts switched off: the note is written and no record kept")
    }

    @Test func theFolderHandsOverAReceiptOnlyForWhatItWrote() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notes = folder.appendingPathComponent("Notes").path
        var kinds: [Receipt.Kind] = []
        let record: (Receipt) -> Void = { kinds.append($0.kind) }
        let open: (URL) -> Void = { _ in }
        _ = NoteFiles.perform(.new, text: "", folder: notes, open: open, record: record)
        _ = NoteFiles.perform(.today, text: "", folder: notes, open: open, record: record)
        _ = NoteFiles.perform(.new, text: "x", folder: "", open: open, record: record)
        #expect(kinds == [], "opening the folder writes nothing")
        _ = NoteFiles.perform(.new, text: "x", folder: notes, open: open, record: record)
        _ = NoteFiles.perform(.today, text: "y", folder: notes, open: open, record: record)
        #expect(kinds == [.note, .noteLine])
    }

    // MARK: A checkpoint

    @Test func aCheckpointSavedLeavesAReceiptThatDeletesItAndNotItsFiles() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        let file = folder.appendingPathComponent("budget.txt")
        try Data("x".utf8).write(to: file)
        model.checkpointing.finderItems = { [file] }

        await model.saveCheckpoint(named: "taxes", note: "call the accountant").value
        let saved = try #require(model.checkpointStore.all.first)
        let receipt = try #require(model.receipts.all.first)
        #expect(receipt.kind == .checkpoint)
        #expect(receipt.subject == "taxes")
        #expect(receipt.title == "Saved the checkpoint taxes")
        #expect(receipt.identifier == saved.id.uuidString)
        #expect(receipt.detail == "1 file")
        #expect(receipt.canUndo)
        #expect(receipt.label().hasSuffix(" · can be deleted"))
        let row = RootItem.receipt(receipt)
        #expect(model.primaryActionTitle(for: row) == "Delete Checkpoint")

        model.activate(row)
        #expect(said.last == "Deleted the checkpoint taxes")
        #expect(model.checkpointStore.all.isEmpty)
        #expect(model.checkpoints.isEmpty, "the search no longer finds it")
        #expect(FileManager.default.fileExists(atPath: file.path), "the files it listed are not touched")
        #expect(model.receipts.all.first?.canUndo == false)
        #expect(model.receipts.all.first?.label().hasSuffix(" · deleted") == true)
    }

    @Test func aCheckpointThatReplacedAnOlderOneSaysThatUndoingBringsNoneBack() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }

        await model.saveCheckpoint(named: "taxes", note: "first").value
        await model.saveCheckpoint(named: "Taxes", note: "second").value
        let receipts = model.receipts.all
        #expect(receipts.map(\.detail) == [
            "a note\nIt replaced an older checkpoint of the same name. Deleting this one does not bring the older one back.",
            "a note",
        ])
        #expect(model.checkpointStore.all.map(\.note) == ["second"])

        try model.undo(#require(receipts.last))
        #expect(said.last == "The checkpoint taxes was already deleted", "the older one went when the newer took its place")
        #expect(model.checkpointStore.all.map(\.note) == ["second"])

        try model.undo(#require(receipts.first))
        #expect(said.last == "Deleted the checkpoint Taxes")
        #expect(model.checkpointStore.all.isEmpty, "and the older one does not come back")
        #expect(model.receipts.all.map(\.canUndo) == [false, false])

        model.settings.keepsReceipts = false
        await model.saveCheckpoint(named: "trip", note: "book the train").value
        #expect(model.checkpointStore.all.map(\.name) == ["trip"])
        #expect(model.receipts.all.count == 2, "receipts switched off: the checkpoint is saved and no record kept")
    }

    @Test func aReceiptFileFromBeforeNotesAndCheckpointsStillReads() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Receipts.json")
        let old = #"[{"id":"6F1B2C3D-0000-4000-8000-000000000002","date":0,"kind":"reminder","subject":"call mom","detail":"No date","reminder":"abc"},"#
            + #"{"id":"6F1B2C3D-0000-4000-8000-000000000001","date":0,"kind":"trash","subject":"a.txt","detail":"~/a.txt","original":"/a","trashed":"/b"}]"#
        try Data(old.utf8).write(to: file)
        let store = ReceiptStore(file: file)
        #expect(store.all.map(\.canUndo) == [true, true])
        #expect(store.all.map(\.size) == [nil, nil])
        store.add(Receipt(date: Date(), kind: .note, subject: "Plan", detail: "", original: "/n/Plan.md", size: 5, modified: Date(timeIntervalSince1970: 7)))
        let again = ReceiptStore(file: file).all
        #expect(again.map(\.kind) == [.note, .reminder, .trash])
        #expect(again.first?.modified == Date(timeIntervalSince1970: 7))
        #expect(again.first?.canUndo == true)
    }
}
