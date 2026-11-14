//
//  PrivateStorageTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// What the user copied or ran stays readable by them alone and out of Time Machine.
struct PrivateStorageTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-private-\(UUID().uuidString)")

    private func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }

    private func permissions(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? Int
    }

    @Test func theClipboardFolderIsLeftOutOfBackups() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = ClipboardFiles.onDisk(folder)
        try files.write(Data("copied".utf8), "history.json", true)
        #expect(isExcludedFromBackup(folder))
        #expect(permissions(folder) == 0o700)
    }

    @Test func receiptsArePrivateAndLeftOutOfBackups() {
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Receipts.json")
        let store = ReceiptStore(file: file)
        store.add(Receipt(date: Date(), kind: .command, subject: "export TOKEN=x", detail: "Done"))
        store.add(Receipt(date: Date(), kind: .command, subject: "ls", detail: "Done"))
        #expect(store.all.count == 2)
        #expect(permissions(file) == 0o600)
        #expect(isExcludedFromBackup(file), "each write replaces the file, so each one marks it again")
    }

    @Test func receiptsFromAnOlderVersionAreProtectedWhenTheStoreOpens() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Receipts.json")
        try Data("[]".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        _ = ReceiptStore(file: file)
        #expect(permissions(file) == 0o600)
        #expect(isExcludedFromBackup(file))
    }

    @Test func theExtensionDataFolderIsPrivate() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        PrivateStorage.restrict(folder, to: 0o700)
        #expect(permissions(folder) == 0o700)
        #expect(!isExcludedFromBackup(folder), "an extension's settings and storage come back with a restore")
    }
}
