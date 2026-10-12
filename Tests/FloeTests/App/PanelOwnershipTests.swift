//
//  PanelOwnershipTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct PanelOwnershipTests {
    /// A work lease follows reference lifetime rather than retaining itself after completion.
    @Test func workLeaseEndsWhenItsOwnerFinishes() {
        weak var released: PanelWork.Lease?
        do {
            let lease = PanelWork.begin()
            released = lease
            withExtendedLifetime(lease) { #expect(PanelWork.isBusy) }
        }
        #expect(released == nil)
    }

    /// Idle detection must see pending work even before its asynchronous task gets scheduled.
    @Test func asyncWorkHoldsALeaseBeforeTheTaskStarts() async {
        let task = PanelWork.perform {
            #expect(PanelWork.isBusy)
            return 42
        }
        #expect(PanelWork.isBusy)
        #expect(await task.value == 42)
    }

    /// Foreground mutations send IDs; only a subsequently saved resident snapshot changes local history.
    @Test func foregroundClipboardMutationsDoNotWriteASecondHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var pinned: [UUID] = []
        var deleted: [UUID] = []
        let store = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false, remote: { packet in
            switch packet {
            case let .pinClipboard(id): pinned.append(id)
            case let .deleteClipboard(id): deleted.append(id)
            default: Issue.record("Unexpected clipboard request")
            }
        })
        let entry = ClipboardEntry(id: UUID(), kind: .text, text: "hello", date: Date(), pinned: false)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(ClipboardFiles.historyName)
        let saved = try JSONEncoder().encode([entry])
        try saved.write(to: file)
        store.reloadMirror()
        store.flush()
        store.togglePin(entry)
        store.delete(entry)
        store.flush()
        #expect(pinned == [entry.id])
        #expect(deleted == [entry.id])
        #expect(store.entries.map(\.id) == [entry.id], "only the resident's snapshot changes the mirror")
        #expect(try Data(contentsOf: file) == saved)
        try Data("[]".utf8).write(to: file)
        store.reloadMirror()
        store.flush()
        #expect(store.entries.isEmpty)
    }

    /// Hotkey routing must leave the resident's search state and results uninitialized.
    @Test func residentHotkeysForwardInsteadOfBuildingForegroundState() throws {
        let scratch = try ScratchDefaults()
        let model = LauncherModel(settings: AppSettings(defaults: scratch.defaults, savesAfterEdits: false), usage: UsageStore(defaults: scratch.defaults), snapshot: CatalogSnapshot(apps: [], commands: []), isResident: true)
        var requests: [PanelRequest] = []
        var localShows = 0
        model.presentInPanelProcess = { requests.append($0) }
        model.showPanel = { localShows += 1 }
        model.runFromHotkey(.emojiSearch)
        model.openMenuBarSearch()
        #expect(try requests == [.builtIn(#require(RootItem.emojiSearch.settingsKey)), .builtIn(#require(RootItem.menuBarSearch.settingsKey))])
        #expect(localShows == 0)
        #expect(!model.isSearchingMenuBar)
        #expect(model.query.isEmpty)
        model.refresh()
        #expect(model.results.isEmpty, "the resident never builds search results")
    }

    /// Real pipe round trips preserve the sequence order used to reject stale idle reports.
    @Test(.timeLimit(.minutes(1))) func privatePipePreservesRequestOrdering() async {
        let up = Pipe()
        let down = Pipe()
        let parent = PanelChannel(input: up.fileHandleForReading, output: down.fileHandleForWriting)
        let child = PanelChannel(input: down.fileHandleForReading, output: up.fileHandleForWriting)
        defer { parent.close(); child.close() }
        var sequences: [Int] = []
        child.receive = { packet in
            if case let .request(_, sequence) = packet {
                child.send(.idle(sequence: sequence))
            }
        }
        parent.start()
        child.start()
        await withCheckedContinuation { continuation in
            parent.receive = { packet in
                if case let .idle(sequence) = packet {
                    sequences.append(sequence)
                    if sequences.count == 2 {
                        continuation.resume()
                    }
                }
            }
            parent.send(.request(.show, sequence: 1))
            parent.send(.request(.hide, sequence: 2))
        }
        #expect(sequences == [1, 2])
    }
}
