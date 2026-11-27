//
//  FileIndexStalenessTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// When Floe's index must not answer: for a query typed past, and while it cannot follow changes on disk.
@MainActor
struct FileIndexStalenessTests {
    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 2000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func ready(_ fixture: IndexFixture) async -> FileIndexService {
        let service = FileIndexService(environment: fixture.environment)
        service.set(on: true)
        await service.settled()
        return service
    }

    @Test func anIndexThatCannotFollowTheDiskLeavesTheAnswersToSpotlightUntilItCan() async throws {
        let fixture = try IndexFixture(files: ["invoice.pdf"])
        let attempts = Mutex(0)
        let starts = Mutex(false)
        var environment = fixture.environment
        let watch = environment.watch
        environment.watch = { root, since, deliver in
            // Each watch fails, as a stream FSEvents refuses, until the test lets the next one start.
            attempts.withLock { $0 += 1 }
            return starts.withLock(\.self) ? watch(root, since, deliver) : nil
        }
        environment.watchRetryDelay = 0.01
        let service = FileIndexService(environment: environment)
        service.set(on: true)
        await waitFor("the watch is tried again") { attempts.withLock(\.self) >= 2 }
        #expect(service.state == .building)
        #expect(service.files(matching: "invoice") == nil, "nil sends the search to Spotlight")
        starts.withLock { $0 = true }
        await waitFor("a watch starts and the index answers") { service.files(matching: "invoice") != nil }
        #expect(service.files(matching: "invoice")?.map(\.name) == ["invoice.pdf"])
        service.set(on: false)
    }

    @Test func whileOneOfTwoIndexesCannotFollowTheDiskBothLeaveTheAnswerToSpotlight() async throws {
        let home = try IndexFixture(files: ["invoice.pdf"])
        let iCloud = try IndexFixture(files: ["drive-invoice.pdf"])
        var refused = iCloud.environment
        refused.watch = { _, _, _ in nil }
        refused.watchRetryDelay = 3600
        let service = FileIndexService(environment: home.environment, alongside: FileIndexService(environment: refused))
        service.set(on: true)
        await service.settled()
        #expect(service.files(matching: "invoice") == nil, "the home index alone would leave iCloud Drive's files out")
        service.set(on: false)
    }

    @Test func emptyingTheFieldDropsTheAnswerToWhatWasTypedBefore() async throws {
        let fixture = try IndexFixture(files: ["invoice.pdf"])
        let search = await FileSearch(index: ready(fixture))
        search.search("invoice")
        search.search("")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!search.results.map(\.name).contains("invoice.pdf"), "the recent files are asked for now, not the old query")
    }
}
