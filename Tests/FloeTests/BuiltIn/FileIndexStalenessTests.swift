//
//  FileIndexStalenessTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
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

    @Test func emptyingTheFieldDropsTheAnswerToWhatWasTypedBefore() async throws {
        let fixture = try IndexFixture(files: ["invoice.pdf"])
        let search = await FileSearch(index: ready(fixture))
        search.search("invoice")
        search.search("")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!search.results.map(\.name).contains("invoice.pdf"), "the recent files are asked for now, not the old query")
    }
}
