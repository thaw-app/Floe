//
//  UsageStoreTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct UsageStoreSaveTests {
    private let scratch: ScratchDefaults

    init() throws {
        scratch = try ScratchDefaults()
    }

    /// Holds the work items the store hands its timer, so a test can run them by hand.
    private final class Timer {
        var waiting: [DispatchWorkItem] = []

        func schedule(delay _: TimeInterval, work: DispatchWorkItem) {
            waiting.append(work)
        }

        func fire() {
            let due = waiting
            waiting = []
            due.forEach { $0.perform() }
        }
    }

    private func savedRecords() -> [String: UsageStore.Record] {
        scratch.defaults.data(forKey: "usage")
            .flatMap { try? JSONDecoder().decode([String: UsageStore.Record].self, from: $0) } ?? [:]
    }

    @Test func usesAreCountedAtOnceAndWrittenDownOncePerBurst() {
        let timer = Timer()
        let store = UsageStore(defaults: scratch.defaults, now: { Date(timeIntervalSince1970: 100) }, later: timer.schedule)

        store.recordUse(of: "app:safari")
        store.recordUse(of: "command:hello/planets")
        store.recordUse(of: "app:safari")

        // Counted in memory at once, so ranking sees them; nothing is written until the timer runs.
        #expect(store.frecency(of: "app:safari") > 0)
        #expect(savedRecords().isEmpty)
        #expect(timer.waiting.count == 3, "each use schedules a timer that cancels the one before it")

        timer.fire()
        let saved = savedRecords()
        #expect(saved["app:safari"]?.count == 2)
        #expect(saved["command:hello/planets"]?.count == 1)
    }

    @Test func flushWritesWhatIsWaitingWithoutItsTimer() {
        let timer = Timer()
        let store = UsageStore(defaults: scratch.defaults, now: { Date(timeIntervalSince1970: 100) }, later: timer.schedule)

        store.recordUse(of: "emoji:🔥")
        store.flush()
        #expect(savedRecords()["emoji:🔥"]?.count == 1)

        // A cancelled timer's work item does nothing once it runs.
        timer.fire()
        #expect(savedRecords()["emoji:🔥"]?.count == 1)
    }

    @Test func whatWasWrittenIsReadBackByTheNextStore() {
        let timer = Timer()
        let first = UsageStore(defaults: scratch.defaults, now: { Date(timeIntervalSince1970: 100) }, later: timer.schedule)
        first.recordUse(of: "app:safari")
        first.flush()

        let second = UsageStore(defaults: scratch.defaults, now: { Date(timeIntervalSince1970: 400) }, later: timer.schedule)
        #expect(second.frecency(of: "app:safari") > 0)
    }
}
