//
//  ClipboardWatcherTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor final class ClipboardWatcherTests {
    private var count = 1
    private var readings: [ClipboardCapture.Reading] = []
    private var reads = 0
    private var delivered: [String] = []
    private var isRecording = true
    private var idle: TimeInterval = 60
    /// Run inside a read, for an app that copies again while the watcher is reading.
    private var duringRead: () -> Void = {}

    private func makeWatcher() -> ClipboardWatcher {
        ClipboardWatcher(
            changeCount: { self.count },
            read: {
                self.reads += 1
                self.duringRead()
                return self.readings.isEmpty ? .empty : self.readings.removeFirst()
            },
            isRecording: { self.isRecording },
            secondsSinceInput: { self.idle }
        ) { reading in
            switch reading {
            case let .copy(capture):
                if case let .text(text) = capture.content {
                    self.delivered.append(text)
                }
            case let .own(id): self.delivered.append("own \(id.uuidString.prefix(4))")
            case .skipped: self.delivered.append("skipped")
            case .empty: self.delivered.append("empty")
            }
        }
    }

    private func copy(_ text: String) -> ClipboardCapture.Reading {
        .copy(ClipboardCapture(content: .text(text), date: Date(), sourceApp: nil))
    }

    @Test func thePasteboardIsReadOnlyAfterItsCountMoves() {
        let watcher = makeWatcher()
        #expect(watcher.tick() == 1, "nothing changed and nobody is typing: the resting pace")
        #expect(reads == 0)
        count = 2
        readings = [copy("one")]
        _ = watcher.tick()
        _ = watcher.tick()
        #expect(reads == 1)
        #expect(delivered == ["one"])
    }

    @Test func thePaceIsTheActiveOneWhileTheKeyboardOrMouseIsInUse() {
        let watcher = makeWatcher()
        idle = 0.4
        #expect(watcher.tick() == 0.25)
        idle = 5
        #expect(watcher.tick() == 1)
    }

    @Test func aPasteboardEmptiedAndFilledAMomentLaterIsNotLost() {
        let watcher = makeWatcher()
        count = 2
        readings = [.empty, .empty, copy("late")]
        #expect(watcher.tick() == 0.25, "an empty read is read again soon, whatever the pace")
        #expect(delivered.isEmpty)
        _ = watcher.tick()
        _ = watcher.tick()
        #expect(delivered == ["late"])
        #expect(reads == 3)
    }

    @Test func aPasteboardThatStaysEmptyIsLeftAfterAFewReads() {
        let watcher = makeWatcher()
        count = 2
        for _ in 0 ..< 10 {
            _ = watcher.tick()
        }
        #expect(reads == 4)
        #expect(delivered.isEmpty)
        #expect(watcher.tick() == 1)
    }

    @Test func aCopyMadeWhileTheLastOneIsReadReplacesIt() {
        let watcher = makeWatcher()
        count = 2
        readings = [copy("half of each"), copy("the newer one")]
        duringRead = { [self] in
            if reads == 1 {
                count = 3
            }
        }
        #expect(watcher.tick() == 0.25)
        #expect(delivered.isEmpty, "what was read while the count moved is not kept")
        _ = watcher.tick()
        #expect(delivered == ["the newer one"])
    }

    @Test func whatIsCopiedWhileTheHistoryIsOffIsNeverRead() {
        let watcher = makeWatcher()
        isRecording = false
        count = 2
        readings = [copy("private")]
        _ = watcher.tick()
        isRecording = true
        _ = watcher.tick()
        #expect(reads == 0)
        count = 3
        readings = [copy("after")]
        _ = watcher.tick()
        #expect(delivered == ["after"])
    }

    @Test func aCopyMadeWhileOffAndNotYetLookedAtIsNotReadOnceRecordingIsBack() {
        let watcher = makeWatcher()
        isRecording = false
        count = 2
        readings = [copy("private")]
        isRecording = true
        watcher.skipToNow()
        _ = watcher.tick()
        #expect(reads == 0)
        count = 3
        readings = [copy("after")]
        _ = watcher.tick()
        #expect(delivered == ["after"])
    }

    @Test func readsLeftForAnEarlierChangeAreDroppedWhenRecordingComesBack() {
        let watcher = makeWatcher()
        count = 2
        readings = [.empty]
        _ = watcher.tick()
        #expect(reads == 1)
        readings = [copy("filled in while off")]
        watcher.skipToNow()
        _ = watcher.tick()
        #expect(reads == 1)
        #expect(delivered.isEmpty)
    }

    @Test func aPrivateCopyAndFloesOwnAreHandedOnOnce() {
        let watcher = makeWatcher()
        count = 2
        readings = [.skipped]
        _ = watcher.tick()
        count = 3
        readings = [.own(UUID())]
        _ = watcher.tick()
        _ = watcher.tick()
        #expect(delivered.count == 2)
        #expect(delivered.first == "skipped")
        #expect(delivered.last?.hasPrefix("own ") == true)
    }
}
