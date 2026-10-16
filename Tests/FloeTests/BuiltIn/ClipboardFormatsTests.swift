//
//  ClipboardFormatsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Synchronization
import Testing

/// Formatted copies, the read that tells an empty pasteboard from a private one, and putting an entry back.
@MainActor
@Suite(.serialized)
final class ClipboardFormatsTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("floe-clipboard-formats-\(UUID().uuidString)", isDirectory: true)
    private let board = NSPasteboard.withUniqueName()
    private let rtf = Data(#"{\rtf1\ansi {\b bold}}"#.utf8)
    private let html = Data("<b>bold</b>".utf8)

    isolated deinit {
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() async -> ClipboardHistoryStore {
        let store = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false)
        await waitFor("the saved list is read") { store.isLoaded }
        return store
    }

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 5000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func formatted(_ text: String, at seconds: TimeInterval) -> ClipboardCapture {
        var capture = ClipboardCapture(content: .text(text), date: Date(timeIntervalSince1970: seconds), sourceApp: "Tests")
        capture.formats = [NSPasteboard.PasteboardType.rtf.rawValue: rtf, NSPasteboard.PasteboardType.html.rawValue: html]
        return capture
    }

    private func formatFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".format") }.sorted()
    }

    private func copyFormattedText(_ text: String) {
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(rtf, forType: .rtf)
        item.setData(html, forType: .html)
        board.writeObjects([item])
    }

    // MARK: Reading

    @Test func aCopyIsReadWithItsFormatting() {
        copyFormattedText("bold")
        guard case let .copy(capture) = ClipboardCapture.reading(board) else {
            Issue.record("a text copy was not read as one")
            return
        }
        #expect(capture.formats == [NSPasteboard.PasteboardType.rtf.rawValue: rtf, NSPasteboard.PasteboardType.html.rawValue: html])
    }

    @Test func formattingTooLargeToKeepLeavesThePlainText() {
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("long", forType: .string)
        item.setData(Data(count: ClipboardCapture.maxFormatBytes + 1), forType: .rtf)
        board.writeObjects([item])
        guard case let .copy(capture) = ClipboardCapture.reading(board) else {
            Issue.record("a text copy was not read as one")
            return
        }
        #expect(capture.formats.isEmpty)
    }

    @Test func anEmptiedPasteboardReadsEmptyAndAPrivateCopyReadsSkipped() {
        board.clearContents()
        guard case .empty = ClipboardCapture.reading(board) else {
            Issue.record("an emptied pasteboard was not read as empty")
            return
        }
        board.setString("", forType: .string)
        guard case .empty = ClipboardCapture.reading(board) else {
            Issue.record("empty text was not read as empty")
            return
        }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.writeObjects([item])
        guard case .skipped = ClipboardCapture.reading(board) else {
            Issue.record("a concealed copy was not skipped")
            return
        }
    }

    // MARK: Keeping

    @Test func textJoinsTheListAtOnceAndAnImageStillBeingConvertedLandsUnderIt() async throws {
        let gate = DispatchSemaphore(value: 0)
        let store = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false, storedPNG: { data in
            gate.wait()
            return ClipboardHistoryStore.storedPNG(data)
        })
        await waitFor("the saved list is read") { store.isLoaded }
        let picture = try #require(NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?.tiffRepresentation)
        store.record(ClipboardCapture(content: .image(picture, fallbackText: nil), date: Date(timeIntervalSince1970: 1), sourceApp: nil))
        store.record(ClipboardCapture(content: .text("after the image"), date: Date(timeIntervalSince1970: 2), sourceApp: nil))
        #expect(store.entries.map(\.text) == ["after the image"], "the text does not wait for the image before it")
        gate.signal()
        await waitFor("the image arrives") { store.entries.count == 2 }
        #expect(store.entries.map(\.kind) == [.text, .image])
    }

    @Test func formattedCopiesAreWrittenBesideTheListAndGoWithTheirEntry() async throws {
        let store = await makeStore()
        store.record(formatted("bold", at: 1))
        store.flush()
        let entry = try #require(store.entries.first)
        #expect(Set(entry.formats?.keys.map(\.self) ?? []) == [NSPasteboard.PasteboardType.rtf.rawValue, NSPasteboard.PasteboardType.html.rawValue])
        #expect(formatFiles() == (entry.formats?.values.sorted() ?? []))
        #expect(store.storedBytes >= rtf.count + html.count)

        // Copied again without formatting, the entry is the same one and the old formatting goes.
        store.record(ClipboardCapture(content: .text("bold"), date: Date(timeIntervalSince1970: 2), sourceApp: nil))
        store.flush()
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.id == entry.id)
        #expect(formatFiles().isEmpty)

        store.record(formatted("bold", at: 3))
        store.flush()
        #expect(formatFiles().count == 2)
        try store.delete(#require(store.entries.first))
        store.flush()
        #expect(formatFiles().isEmpty)
    }

    @Test func aFormattedCopyThatCannotBeWrittenIsNotNamed() async {
        var files = ClipboardFiles.onDisk(directory)
        let write = files.write
        files.write = { data, name, atomically in
            if name.hasSuffix(".format") {
                throw CocoaError(.fileWriteNoPermission)
            }
            try write(data, name, atomically)
        }
        let store = ClipboardHistoryStore(files: files, monitorsPasteboard: false)
        await waitFor("the saved list is read") { store.isLoaded }
        store.record(formatted("bold", at: 1))
        store.flush()
        #expect(store.entries.first?.text == "bold")
        #expect(store.entries.first?.formats?.isEmpty ?? true)
        let second = await makeStore()
        #expect(second.entries.first?.formats?.isEmpty ?? true, "the saved list does not name them either")
    }

    @Test func formattedCopiesAreWrittenBeforeTheListThatNamesThem() async {
        let held = DispatchSemaphore(value: 0)
        let isFirst = Mutex(true)
        let written = Mutex<[String]>([])
        var files = ClipboardFiles.onDisk(directory)
        let write = files.write
        files.write = { data, name, atomically in
            // The first formatted copy holds the worker, so the next copy is asked for behind a waiting save.
            if name.hasSuffix(".format"), isFirst.withLock({ defer { $0 = false }; return $0 }) {
                held.wait()
            }
            written.withLock { $0.append(name.hasSuffix(".format") ? "format" : name) }
            try write(data, name, atomically)
        }
        let store = ClipboardHistoryStore(files: files, monitorsPasteboard: false)
        await waitFor("the saved list is read") { store.isLoaded }
        store.record(formatted("first", at: 1))
        store.record(formatted("second", at: 2))
        held.signal()
        store.flush()
        #expect(written.withLock { $0 } == Array(repeating: "format", count: 4) + [ClipboardFiles.historyName])
    }

    @Test func aFormattedCopyWhoseFileIsGoneLoadsAsItsText() async throws {
        let first = await makeStore()
        first.record(formatted("bold", at: 1))
        first.flush()
        for name in formatFiles().prefix(1) {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        let second = await makeStore()
        #expect(second.entries.first?.text == "bold")
        #expect(second.entries.first?.formats?.count == 1)
    }

    // MARK: Putting back

    @Test func anEntryGoesBackWithItsFormattingAndIsKnownAsFloesOwn() async throws {
        let store = await makeStore()
        store.record(formatted("bold", at: 1))
        store.record(ClipboardCapture(content: .text("newer"), date: Date(timeIntervalSince1970: 2), sourceApp: nil))
        store.flush()
        let entry = try #require(store.entries.last)
        #expect(ClipboardHistoryStore.writeToPasteboard(entry, board: board, directory: directory))
        #expect(board.string(forType: .string) == "bold")
        #expect(board.data(forType: .rtf) == rtf)
        #expect(board.data(forType: .html) == html)

        guard case let .own(id) = ClipboardCapture.reading(board) else {
            Issue.record("Floe's own write was not recognised")
            return
        }
        #expect(id == entry.id)
        store.take(.own(id))
        #expect(store.entries.map(\.text) == ["bold", "newer"], "put back, it only moves to the top")
        #expect(store.entries.first?.formats == entry.formats)
        #expect(formatFiles().count == 2)
    }

    @Test func aMirrorLeavesTheOrderToTheStoreThatWritesTheHistory() async throws {
        let writer = await makeStore()
        writer.record(ClipboardCapture(content: .text("older"), date: Date(timeIntervalSince1970: 1), sourceApp: nil))
        writer.record(ClipboardCapture(content: .text("newer"), date: Date(timeIntervalSince1970: 2), sourceApp: nil))
        writer.flush()
        let mirror = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false, remote: { _ in })
        mirror.apply(.reload)
        await waitFor("the mirror reads the list") { mirror.entries.count == 2 }
        let older = try #require(mirror.entries.last)
        mirror.take(.own(older.id))
        #expect(mirror.entries.map(\.text) == ["newer", "older"])
    }

    @Test func theResidentSaysWhichEntriesChangedAndTheMirrorTakesOnlyThose() async throws {
        let writer = await makeStore()
        writer.record(ClipboardCapture(content: .text("older"), date: Date(timeIntervalSince1970: 1), sourceApp: nil))
        writer.flush()
        let mirror = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false, remote: { _ in })
        mirror.apply(.reload)
        await waitFor("the mirror reads the list") { mirror.entries.count == 1 }

        var changes: [ClipboardChange] = []
        writer.onSaved = { changes.append($0) }
        writer.record(ClipboardCapture(content: .text("newer"), date: Date(timeIntervalSince1970: 2), sourceApp: nil))
        let older = try #require(writer.entries.last)
        writer.delete(older)
        writer.flush()
        var changed: [String?] = []
        var removed: [UUID] = []
        for change in changes {
            guard case let .entries(entries, gone) = change else {
                Issue.record("a save sends the entries, not a reload")
                return
            }
            changed += entries.map(\.text)
            removed += gone
        }
        #expect(changed == ["newer"])
        #expect(removed == [older.id])
        try Data("[]".utf8).write(to: directory.appendingPathComponent(ClipboardFiles.historyName))
        changes.forEach(mirror.apply)
        #expect(mirror.entries.map(\.text) == ["newer"], "taken from the changes, not from the file")
    }

    @Test func aChangeBeforeTheMirrorsFirstReadMakesItReadAgain() async {
        let writer = await makeStore()
        writer.record(ClipboardCapture(content: .text("saved"), date: Date(timeIntervalSince1970: 1), sourceApp: nil))
        writer.flush()
        let mirror = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false, remote: { _ in })
        mirror.apply(.entries(changed: [], removed: [UUID()]))
        await waitFor("the mirror reads the list") { mirror.entries.map(\.text) == ["saved"] }
    }

    @Test func listsWithTheSameEntriesAreNoChange() {
        let entry = ClipboardEntry(id: UUID(), kind: .text, text: "same", date: Date(), pinned: false)
        var pinned = entry
        pinned.pinned = true
        #expect(ClipboardChange.between([entry], [entry]) == nil)
        #expect(ClipboardChange.between([entry], [pinned]) == .entries(changed: [pinned], removed: []))
        #expect(ClipboardChange.between([entry], []) == .entries(changed: [], removed: [entry.id]))
    }

    @Test func filesGoBackMarkedToo() {
        let entry = ClipboardEntry.files(["/tmp/floe-report.pdf"], date: Date(), sourceApp: nil)
        #expect(ClipboardHistoryStore.writeToPasteboard(entry, board: board, directory: directory))
        guard case let .own(id) = ClipboardCapture.reading(board) else {
            Issue.record("Floe's own write was not recognised")
            return
        }
        #expect(id == entry.id)
        #expect((board.readObjects(forClasses: [NSURL.self]) as? [URL])?.map(\.path) == ["/tmp/floe-report.pdf"])
    }

    @Test func anEntryWithNothingToWriteIsNotACopy() {
        let entry = ClipboardEntry(id: UUID(), kind: .image, imageFile: "gone.png", date: Date(), pinned: false)
        #expect(!ClipboardHistoryStore.writeToPasteboard(entry, board: board, directory: directory))
    }

    // MARK: Pasting

    @Test func theKeyIsPressedOnceFloeIsOutOfTheWay() async {
        var asked = 0
        var pressed = 0
        ClipboardHistoryStore.pasteWhenClear(isClear: {
            asked += 1
            return asked == 3
        }, press: { pressed += 1 })
        #expect(pressed == 0, "never at once")
        await waitFor("the key") { pressed == 1 }
        #expect(asked == 3)
    }
}
