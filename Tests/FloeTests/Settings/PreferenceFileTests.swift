//
//  PreferenceFileTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct PreferenceFileTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-preference-file-\(UUID().uuidString)")

    private var file: URL {
        folder.appendingPathComponent("preferences.json")
    }

    private func plant(_ text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func values() -> [String: Any]? {
        if case let .values(values) = PreferenceFile.read(file) { return values }
        return nil
    }

    @Test func aMissingFileIsWrittenOnUpdate() {
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .missing = PreferenceFile.read(file) else {
            Issue.record("a file that is not there reads as missing")
            return
        }

        #expect(PreferenceFile.update(file) { $0.merging(["a": 1]) { _, new in new } })

        #expect(values()?["a"] as? Int == 1)
    }

    @Test func anUpdateKeepsWhatWasThere() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try plant(#"{"a":1}"#)
        #expect(values()?["a"] as? Int == 1)

        #expect(PreferenceFile.update(file) { $0.merging(["b": 2]) { _, new in new } })

        #expect(values()?["a"] as? Int == 1)
        #expect(values()?["b"] as? Int == 2)
    }

    @Test func aFileThatIsNotJSONIsNeverWrittenOver() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try plant("not json")
        guard case .unreadable = PreferenceFile.read(file) else {
            Issue.record("a file that is not JSON reads as unreadable")
            return
        }

        #expect(!PreferenceFile.update(file) { _ in ["b": 2] })

        #expect(try Data(contentsOf: file) == Data("not json".utf8))
    }

    @Test func jsonThatIsNotAnObjectIsNeverWrittenOver() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try plant("[1,2]")
        guard case .unreadable = PreferenceFile.read(file) else {
            Issue.record("JSON that is not an object reads as unreadable")
            return
        }

        #expect(!PreferenceFile.update(file) { _ in ["b": 2] })

        #expect(try Data(contentsOf: file) == Data("[1,2]".utf8))
    }

    @Test func aWriteMakesTheFolderItGoesIn() {
        defer { try? FileManager.default.removeItem(at: folder) }
        let nested = folder.appendingPathComponent("weather").appendingPathComponent("preferences.json")

        #expect(PreferenceFile.write(["a": 1], to: nested))

        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test func aNullRemovesItsKey() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try plant(#"{"a":1,"b":2}"#)

        #expect(PreferenceFile.update(file) { $0.merging(["a": NSNull()]) { _, new in new } })

        #expect(values()?["a"] == nil)
        #expect(values()?["b"] as? Int == 2)
    }
}
