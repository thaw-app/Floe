//
//  ClipboardHistoryModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor
@Suite("Clipboard history view state")
final class ClipboardHistoryModelTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("floe-clipboard-model-tests-\(UUID().uuidString)", isDirectory: true)
    private let scratch = MemoryDefaults()
    private lazy var store = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A model over a scratch store that holds the given copies, oldest first.
    private func makeModel(_ copies: [String] = ["alpha", "beta", "gamma"]) async -> ClipboardHistoryModel {
        for (index, copy) in copies.enumerated() {
            store.record(ClipboardCapture(content: .text(copy), date: Date(timeIntervalSince1970: TimeInterval(index + 1)), sourceApp: "Tests"))
        }
        for _ in 0 ..< 5000 where store.entries.count < copies.count {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return ClipboardHistoryModel(usage: UsageStore(defaults: scratch)) { [store] in store }
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func theEntriesAreNewestFirstAndAQueryNarrowsThemAndResetsTheSelection() async {
        let model = await makeModel()
        #expect(model.filteredEntries().map(\.text) == ["gamma", "beta", "alpha"])
        model.selection = 2
        #expect(model.selectedEntry?.text == "alpha")
        model.query = "bet"
        #expect(model.filteredEntries().map(\.text) == ["beta"])
        #expect(model.selection == 0)
        #expect(model.selectedEntry?.text == "beta")
    }

    @Test func theListKeptBetweenPassesFollowsTheQueryAndTheCopies() async throws {
        let model = await makeModel()
        model.query = "a"
        #expect(model.filteredEntries().map(\.text) == ["gamma", "beta", "alpha"])
        model.query = "al"
        #expect(model.filteredEntries().map(\.text) == ["alpha"])
        model.query = ""
        #expect(model.filteredEntries().count == 3, "a query typed back is filtered again")
        try model.togglePin(#require(model.filteredEntries().last))
        #expect(model.filteredEntries().first?.text == "alpha", "a pin changes the copies, so the list is made again")
    }

    @Test func anImagePreviewIsDecodedAtThePreviewsSizeWithItsFileSize() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("wide.png")
        let context = try #require(CGContext(
            data: nil, width: 2000, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let picture = try #require(context.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]))
        try png.write(to: file)
        let preview = await ClipboardHistoryStore.preview(of: file, maxPixels: 500)
        #expect(preview.image?.width == 500)
        #expect(preview.image?.height == 125)
        #expect(preview.bytes == png.count)
        let missing = await ClipboardHistoryStore.preview(of: directory.appendingPathComponent("gone.png"), maxPixels: 500)
        #expect(missing.image == nil && missing.bytes == nil)
    }

    @Test func theArrowsMoveTheSelectionAndStopAtTheEnds() async throws {
        let model = await makeModel()
        #expect(try model.handleKey(key(126)))
        #expect(model.selection == 0)
        for _ in 0 ..< 5 {
            #expect(try model.handleKey(key(125)))
        }
        #expect(model.selection == 2)
        #expect(try !model.handleKey(key(0)), "a letter goes on to the search field")
    }

    @Test func deleteRemovesTheSelectedCopyAndKeepsTheSelectionInsideTheList() async throws {
        let model = await makeModel()
        model.selection = 2
        #expect(try model.handleKey(key(51)))
        #expect(model.filteredEntries().map(\.text) == ["gamma", "beta"])
        #expect(model.selection == 1)
    }

    @Test func aCopyArrivingWhileTheListIsOpenLeavesTheSelectionOnTheSameCopy() async {
        let model = await makeModel()
        model.selection = 1
        store.record(ClipboardCapture(content: .text("delta"), date: Date(timeIntervalSince1970: 10), sourceApp: "Tests"))
        model.entriesChanged()
        #expect(model.selectedEntry?.text == "beta")
        if let beta = model.selectedEntry {
            store.delete(beta)
        }
        model.entriesChanged()
        #expect(model.selectedEntry?.text == "alpha", "a copy that is gone leaves the selection in its place")
    }

    @Test func pinningACopyPutsItFirst() async throws {
        let model = await makeModel()
        model.selection = 2
        try model.togglePin(#require(model.selectedEntry))
        #expect(model.filteredEntries().map(\.text) == ["alpha", "gamma", "beta"])
    }

    @Test func escapeClearsAQueryFirstAndOnlyThenLeavesTheHistory() async throws {
        let model = await makeModel([])
        var closed = 0
        model.host.close = { closed += 1 }
        model.query = "bet"
        #expect(try model.handleKey(key(53)))
        #expect(model.query.isEmpty)
        #expect(closed == 0)
        #expect(try model.handleKey(key(53)))
        #expect(closed == 1)
    }

    @Test func returnWithNothingSelectedIsConsumedAndLeavesThePanelAlone() async throws {
        let model = await makeModel([])
        var dismissed = 0
        model.host.dismiss = { dismissed += 1 }
        #expect(try model.handleKey(key(36)))
        #expect(try model.handleKey(key(51)))
        #expect(dismissed == 0)
    }

    @Test func theLauncherShowsTheHistoryAndTypingInItDoesNotRepublishTheLauncher() throws {
        let settings = AppSettings(defaults: scratch)
        settings.clipboardHistoryIsParked = false
        let launcher = LauncherModel(
            settings: settings, usage: UsageStore(defaults: scratch),
            snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: []
        )
        launcher.clipboardHistory.query = "left over"
        launcher.clipboardHistory.selection = 4
        launcher.openClipboardHistory()
        #expect(launcher.isShowingClipboardHistory)
        #expect(launcher.clipboardHistory.query.isEmpty, "the history opens on everything")
        #expect(launcher.clipboardHistory.selection == 0)

        var changes = 0
        let subscription = launcher.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        launcher.clipboardHistory.query = "bet"
        launcher.clipboardHistory.selection = 0
        #expect(changes == 0)

        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.clipboardHistory.query.isEmpty)
        #expect(launcher.isShowingClipboardHistory)
        #expect(try launcher.handleKey(key(53)))
        #expect(!launcher.isShowingClipboardHistory)
    }

    @Test func theCopiesAreGroupedByDayNewestDayFirstAndKeepTheirOrderInsideADay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let copy: (String, Int, TimeInterval) -> ClipboardEntry = { text, daysAgo, seconds in
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return ClipboardEntry(id: UUID(), kind: .text, text: text, date: day.addingTimeInterval(seconds), pinned: false)
        }
        let entries = [copy("five days, late", 5, 90), copy("today, early", 0, 1), copy("three days", 3, 5), copy("yesterday", 1, 60), copy("today, late", 0, 2), copy("five days, early", 5, 30)]
        let groups = ClipboardHistoryView.dayGroups(entries, calendar: calendar)
        #expect(groups.map { $0.entries.map(\.text) } == [["today, early", "today, late"], ["yesterday"], ["three days"], ["five days, late", "five days, early"]])
        #expect(groups.prefix(2).map(\.title) == [String(localized: "Today", bundle: .floe), String(localized: "Yesterday", bundle: .floe)])
        #expect(Set(groups.map(\.title)).count == 4, "each day under its own heading")
        #expect(ClipboardHistoryView.dayGroups([], calendar: calendar).isEmpty)
    }
}
