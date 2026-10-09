//
//  ExtensionAccessTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ExtensionAccessTests {
    private func scratchStore() -> (ExtensionAccessStore, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-access-\(UUID().uuidString)/ExtensionAccess.json")
        return (ExtensionAccessStore(file: file), file)
    }

    @Test func aReportAddsOnlyWhatIsNewAndSaysWhetherAnythingWas() {
        var access = ExtensionAccess()
        let first = Date(timeIntervalSince1970: 100)
        do {
            let added = access.add(["type": "access", "hosts": ["hnrss.org"], "programs": ["git", ""]], at: first)
            #expect(added)
        }
        #expect(access.hosts == ["hnrss.org"])
        #expect(access.programs == ["git"], "an empty name is no program")
        #expect(access.since == first && access.latest == first)

        do {
            let added = access.add(["hosts": ["hnrss.org"]], at: Date(timeIntervalSince1970: 200))
            #expect(!added, "seen before: nothing to write")
        }
        #expect(access.latest == first)

        do {
            let added = access.add(["hosts": ["api.github.com"], "reads": ["~/Documents"], "writes": ["~/Downloads"]], at: Date(timeIntervalSince1970: 300))
            #expect(added)
        }
        #expect(access.hosts == ["api.github.com", "hnrss.org"], "kept sorted")
        #expect(access.reads == ["~/Documents"] && access.writes == ["~/Downloads"])
        #expect(access.since == first, "the first day stays")
        #expect(access.latest == Date(timeIntervalSince1970: 300))
        do {
            let added = access.add(["hosts": "not a list", "reads": [1, 2]], at: Date())
            #expect(!added, "a report that is not what it should be adds nothing")
        }
    }

    @Test func anExtensionGoneWrongDoesNotFillTheRecord() {
        var access = ExtensionAccess()
        _ = access.add(["hosts": (0 ..< 500).map { "host\($0).example" }], at: Date())
        #expect(access.hosts.count == ExtensionAccess.limit)
    }

    @Test func theRecordIsKeptByExtensionInAFileAndForgotten() {
        let (store, file) = scratchStore()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(store.access(of: "hacker-news").isEmpty)
        store.record(["hosts": ["hnrss.org"]], for: "hacker-news")
        store.record(["programs": ["pass-cli"]], for: "proton-pass")
        #expect(ExtensionAccessStore(file: file).access(of: "hacker-news").hosts == ["hnrss.org"], "the settings window reads the same file")
        #expect(store.access(of: "proton-pass").programs == ["pass-cli"])

        let written = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        store.record(["hosts": ["hnrss.org"]], for: "hacker-news")
        #expect((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date == written, "nothing new, nothing written")

        store.forget("hacker-news")
        #expect(store.access(of: "hacker-news").isEmpty)
        #expect(!store.access(of: "proton-pass").isEmpty, "the others are kept")
    }

    @Test func forgettingEverythingLeavesNoRecordAndNoFile() {
        let (store, file) = scratchStore()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.forgetAll()
        #expect(store.access(of: "hacker-news").isEmpty, "nothing to forget is no failure")
        store.record(["hosts": ["hnrss.org"]], for: "hacker-news")
        store.record(["programs": ["pass-cli"]], for: "proton-pass")
        store.forgetAll()
        #expect(store.access(of: "hacker-news").isEmpty)
        #expect(store.access(of: "proton-pass").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        store.record(["hosts": ["hnrss.org"]], for: "hacker-news")
        #expect(store.access(of: "hacker-news").hosts == ["hnrss.org"], "and recording starts again from nothing")
    }

    @MainActor
    @Test func theRecordIsOnUntilSwitchedOffAndSwitchingItOffForgetsWhatWasRecorded() throws {
        let suite = "floe-access-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, file) = scratchStore()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.recordsExtensionAccess, "on until the user switches it off")

        store.record(["hosts": ["hnrss.org"]], for: "hacker-news")
        settings.setRecordsExtensionAccess(true, store: store)
        #expect(!store.access(of: "hacker-news").isEmpty, "switching it on forgets nothing")
        settings.setRecordsExtensionAccess(false, store: store)
        #expect(!settings.recordsExtensionAccess)
        #expect(store.access(of: "hacker-news").isEmpty)
        settings.save()
        #expect(!AppSettings(defaults: defaults, savesAfterEdits: false).recordsExtensionAccess, "the switch is kept with the settings")

        let entry = try #require(SearchIndex.staticEntries.first { $0.id == "privacy.recordsExtensionAccess" })
        #expect(entry.title == "Record what extensions reach")
        #expect(entry.pane == .privacy)
        #expect(entry.keywords.contains("extensions"))
    }

    @Test func thePageSaysSinceWhen() {
        #expect(ExtensionAccessSection.since(nil) == "Recorded")
        #expect(ExtensionAccessSection.since(Date(timeIntervalSince1970: 0)).hasPrefix("Recorded since "))
    }
}
