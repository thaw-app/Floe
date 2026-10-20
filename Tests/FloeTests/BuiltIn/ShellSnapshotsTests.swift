//
//  ShellSnapshotsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// Drives the store with readers of its own, so a read can be held and counted.
@MainActor
struct ShellSnapshotsTests {
    @Test func twentyAsksForOneFolderReadItOnce() async throws {
        let reads = Mutex(0)
        // The clock stands still: on a busy machine the answer could otherwise age past its lifetime and be read again.
        let store = ShellSnapshots(now: { Date(timeIntervalSince1970: 0) }, readEntries: { _ in
            let count: Int = reads.withLock { state in
                state += 1
                return state
            }
            return ["row-\(count)"]
        })
        for _ in 0 ..< 20 {
            #expect(store.entries("folder").isEmpty, "the answer arrives when the read lands")
        }
        // The one read lands, and it is the only one the asks share.
        try await landed(store, "folder", is: "row-1")
        #expect(reads.withLock { $0 } == 1, "the asks share the read that is on its way")
    }

    @Test func anUnchangedAnswerStillCoversItsLifetime() async throws {
        let clock = Mutex(Date(timeIntervalSince1970: 0))
        let reads = Mutex(0)
        let store = ShellSnapshots(
            now: { clock.withLock { $0 } },
            readEntries: { _ in
                reads.withLock { $0 += 1 }
                return ["row"]
            }
        )
        func advance(by seconds: TimeInterval) {
            clock.withLock { $0 = $0.addingTimeInterval(seconds) }
        }
        // The read of the first ask lands, and its freshness is counted from its landing.
        _ = store.entries("same")
        try await landed(store, "same", is: "row")
        // Past the lifetime, the answer is read again — and its freshness is renewed even though
        // what came back is the same, so asks within the next lifetime wait for no read.
        advance(by: 3)
        _ = store.entries("same")
        // The answer is the same, so the second read is what is waited for, then its landing on the main actor.
        // A busy machine can take seconds to start it.
        for _ in 0 ..< 500 where reads.withLock({ $0 }) < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(50))
        advance(by: 1)
        _ = store.entries("same")
        advance(by: 0.5)
        _ = store.entries("same")
        #expect(reads.withLock { $0 } == 2, "two reads: one at the start, one at the expiry; the renewed one covers the rest")
    }

    /// Waits for a read to land, by the only thing visible from outside: the store serving its answer.
    private func landed(_ store: ShellSnapshots, _ folder: String, is value: String) async throws {
        for _ in 0 ..< 500 {
            if store.entries(folder) == [value] {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("the read that writes \(value) never landed")
    }

    @Test func aFolderReadLandsEvenWhenAnotherFoldersReadFinishedLast() async throws {
        let store = ShellSnapshots(readEntries: { folder in
            if folder == "slow" {
                Thread.sleep(forTimeInterval: 0.15)
            }
            return ["\(folder)-row"]
        })
        #expect(store.entries("slow").isEmpty, "the read of the slow folder is on its way")
        #expect(store.entries("fast") == [], "the fast folder's read has only just started")
        try await Task.sleep(for: .milliseconds(400))
        #expect(store.entries("fast") == ["fast-row"])
        #expect(store.entries("slow") == ["slow-row"], "a folder whose read started before another's is not thrown out by it")
    }
}
