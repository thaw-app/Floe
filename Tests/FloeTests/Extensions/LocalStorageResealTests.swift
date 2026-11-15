//
//  LocalStorageResealTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
@testable import Floe
import Foundation
import SQLite3
import Testing

/// An extension's LocalStorage rows moved from the old shared key to its own, in the runtime's layout.
struct LocalStorageResealTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-reseal-\(UUID().uuidString)")
    private var file: URL {
        folder.appendingPathComponent("local-storage.sqlite")
    }

    private let legacy = SymmetricKey(data: Data(repeating: 1, count: 32))
    private let own = SymmetricKey(data: Data(repeating: 3, count: 32))
    private let other = SymmetricKey(data: Data(repeating: 5, count: 32))

    /// Made with node:crypto, outside this code: "abc" for the item token, under 32 bytes of 0x01 with an IV of
    /// 12 bytes of 0x02. The runtime's tests read the same value back.
    private let pinned = "sealed1:AgICAgICAgICAgICvVzZaAPRw6HYcFytWCZRPiW3qypo"

    private func database(_ sql: [String]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        defer { sqlite3_close_v2(handle) }
        try #require(sqlite3_open(file.path, &handle) == SQLITE_OK)
        for statement in sql {
            try #require(sqlite3_exec(handle, statement, nil, nil, nil) == SQLITE_OK, "\(statement)")
        }
    }

    private func items(_ rows: [(String, String)]) throws {
        let inserts = rows.map { "INSERT INTO items (key, value) VALUES ('\($0.0)', '\($0.1)')" }
        try database(["CREATE TABLE items (key TEXT PRIMARY KEY, value TEXT NOT NULL)"] + inserts)
    }

    private func stored() -> [String: String] {
        var handle: OpaquePointer?
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        sqlite3_prepare_v2(handle, "SELECT key, value FROM items", -1, &statement, nil)
        var rows: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            rows[String(cString: sqlite3_column_text(statement, 0))] = String(cString: sqlite3_column_text(statement, 1))
        }
        return rows
    }

    private func sealed(_ json: String, _ itemKey: String, _ key: SymmetricKey) throws -> String {
        try LocalStorageReseal.seal(json: json, itemKey: itemKey, key: key)
    }

    @Test func aRowIsSealedAndOpenedInTheRuntimesLayout() throws {
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 2, count: 12))
        #expect(try LocalStorageReseal.seal(json: "\"abc\"", itemKey: "token", key: legacy, nonce: nonce) == pinned)
        #expect(LocalStorageReseal.open(pinned, itemKey: "token", key: legacy) == "\"abc\"")
        #expect(LocalStorageReseal.open(pinned, itemKey: "other", key: legacy) == nil, "the item's key is bound in")
        #expect(LocalStorageReseal.open("\"abc\"", itemKey: "token", key: legacy) == nil)
        #expect(LocalStorageReseal.open("sealed1:AgIC", itemKey: "token", key: legacy) == nil)
    }

    @Test func onlyRowsSealedUnderTheOldKeyAreSealedAgainUnderTheirOwn() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let mine = try sealed("2", "mine", own)
        let theirs = try sealed("4", "theirs", other)
        try items([("old", sealed("1", "old", legacy)), ("mine", mine), ("plain", "\"1\""), ("theirs", theirs)])
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .done(resealed: 1))
        let after = stored()
        #expect(LocalStorageReseal.open(after["old"] ?? "", itemKey: "old", key: own) == "1")
        #expect(LocalStorageReseal.open(after["old"] ?? "", itemKey: "old", key: legacy) == nil)
        #expect(after["mine"] == mine)
        #expect(after["plain"] == "\"1\"")
        #expect(after["theirs"] == theirs)
    }

    @Test func aSecondRunChangesNothing() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try items([("old", sealed("1", "old", legacy))])
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .done(resealed: 1))
        let first = stored()
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .done(resealed: 0))
        #expect(stored() == first)
    }

    @Test func theOldCiphertextIsNotLeftInTheFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try sealed("\"" + String(repeating: "x", count: 2000) + "\"", "old", legacy)
        try items([("old", old)])
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .done(resealed: 1))
        let bytes = try Data(contentsOf: file)
        #expect(bytes.range(of: Data(old.dropFirst(LocalStorageReseal.prefix.count).prefix(64).utf8)) == nil)
    }

    @Test func aKeyWithANulInsideIsSealedAgainWhole() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = "account\u{0}token"
        let old = try sealed("1", key, legacy)
        try database([
            "CREATE TABLE items (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
            "INSERT INTO items (key, value) VALUES ('account' || char(0) || 'token', '\(old)')",
        ])
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .done(resealed: 1))
        let after = try #require(value(where: "key = 'account' || char(0) || 'token'"))
        #expect(LocalStorageReseal.open(after, itemKey: key, key: own) == "1")
    }

    private func value(where condition: String) -> String? {
        var handle: OpaquePointer?
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "SELECT value FROM items WHERE \(condition)", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }

    @Test func aFileThatIsNotThereIsNotMade() {
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .missing)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aFileThatIsNotADatabaseIsLeftAsItIs() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let noise = Data((0 ..< 4096).map { _ in UInt8.random(in: 0 ... 255) })
        try noise.write(to: file)
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .unreadable)
        #expect(try Data(contentsOf: file) == noise)
    }

    @Test func aDatabaseWithoutItsTableHasNothingToDo() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try database(["CREATE TABLE migration (done INTEGER NOT NULL UNIQUE)"])
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own) == .done(resealed: 0))
    }

    @Test func aDatabaseAnotherProcessHoldsIsLeftForLater() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try sealed("1", "old", legacy)
        try items([("old", old)])
        var holder: OpaquePointer?
        try #require(sqlite3_open(file.path, &holder) == SQLITE_OK)
        try #require(sqlite3_exec(holder, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        #expect(LocalStorageReseal.reseal(file: file, from: legacy, to: own, busyWait: 50) == .busy)
        sqlite3_exec(holder, "ROLLBACK", nil, nil, nil)
        sqlite3_close_v2(holder)
        #expect(stored()["old"] == old)
    }
}
