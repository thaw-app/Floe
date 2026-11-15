//
//  StorageMigrationTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
@testable import Floe
import Foundation
import Synchronization
import Testing

/// The move off the old shared storage key: which extensions get their own key, and when the old key goes.
struct StorageMigrationTests {
    private static let old = Data(repeating: 1, count: 32).base64EncodedString()
    private static let root = Data(repeating: 3, count: 32).base64EncodedString()

    /// The keychain and the data folder, in memory: what was asked, and how each file goes.
    private final class Fake: Sendable {
        struct State {
            var legacy: StorageKey.Legacy = .key(StorageMigrationTests.old)
            var root: StorageKey.Access = .key(StorageMigrationTests.root)
            /// Nil is a data folder that could not be read.
            var files: [StorageMigration.StorageFile]? = []
            var outcomes: [String: LocalStorageReseal.Outcome] = [:]
            var resealed: [(file: URL, from: SymmetricKey, to: SymmetricKey)] = []
            var retired = 0
        }

        let state = Mutex(State())

        func files(_ names: String...) {
            state.withLock { $0.files = names.map { StorageMigration.StorageFile(name: $0, file: URL(fileURLWithPath: "/data/\($0)/local-storage.sqlite")) } }
        }

        var retired: Int {
            state.withLock { $0.retired }
        }

        var resealCount: Int {
            state.withLock { $0.resealed.count }
        }

        var migration: StorageMigration {
            StorageMigration(environment: StorageMigration.Environment(
                legacy: { self.state.withLock { $0.legacy } },
                root: { self.state.withLock { $0.root } },
                storageFiles: { self.state.withLock { $0.files } },
                reseal: { file, from, to in
                    self.state.withLock { state in
                        state.resealed.append((file, from, to))
                        return state.outcomes[file.deletingLastPathComponent().lastPathComponent] ?? .done(resealed: 1)
                    }
                },
                retire: { self.state.withLock { $0.retired += 1 } }
            ))
        }
    }

    private let fake = Fake()

    @Test func withoutAnOldKeyEveryExtensionHasItsOwnAndNothingIsMoved() {
        fake.state.withLock { $0.legacy = .none }
        fake.files("github")
        let migration = fake.migration
        #expect(migration.allows("github"))
        migration.run()
        migration.clipboardSettled(true)
        #expect(migration.allows("github"))
        #expect(fake.resealCount == 0)
        #expect(fake.retired == 0)
    }

    @Test func withAnOldKeyNoExtensionHasItsOwnBeforeTheMove() {
        fake.files("github")
        #expect(!fake.migration.allows("github"))
    }

    @Test func theOldKeyGoesOnceEverythingIsDoneInEitherOrder() {
        fake.files("github", "notes")
        let migration = fake.migration
        migration.run()
        #expect(fake.retired == 0, "the clipboard folder is not done yet")
        migration.clipboardSettled(true)
        #expect(fake.retired == 1)
        migration.clipboardSettled(true)
        #expect(fake.retired == 1, "once")
        #expect(migration.allows("github"))
        #expect(migration.allows("anything"))

        let other = Fake()
        other.files("github")
        let clipboardFirst = other.migration
        clipboardFirst.clipboardSettled(true)
        clipboardFirst.run()
        #expect(other.retired == 1)
    }

    @Test func aFileAnotherProcessHeldKeepsThatExtensionLockedAndTheOldKey() {
        fake.files("GitHub", "notes")
        fake.state.withLock { $0.outcomes["GitHub"] = .busy }
        let migration = fake.migration
        migration.run()
        migration.clipboardSettled(true)
        #expect(!migration.allows("github"))
        #expect(!migration.allows("GitHub"))
        #expect(migration.allows("notes"))
        #expect(fake.retired == 0)
    }

    @Test func aMissingOrUnreadableFileCountsAsDone() {
        fake.files("gone", "broken")
        fake.state.withLock { $0.outcomes = ["gone": .missing, "broken": .unreadable] }
        let migration = fake.migration
        migration.run()
        migration.clipboardSettled(true)
        #expect(fake.retired == 1)
        #expect(migration.allows("broken"))
    }

    @Test func aClipboardThatIsNotDoneKeepsTheOldKeyButNotTheExtensionsWaiting() {
        fake.files("github")
        let migration = fake.migration
        migration.run()
        migration.clipboardSettled(false)
        #expect(fake.retired == 0)
        #expect(migration.allows("github"))
    }

    @Test func anOldKeyThatCannotBeReadLocksEveryExtensionAndMovesNothing() {
        fake.state.withLock { $0.legacy = .unreadable }
        fake.files("github")
        let migration = fake.migration
        migration.run()
        migration.clipboardSettled(true)
        #expect(!migration.allows("github"))
        #expect(!migration.allows("notes"))
        #expect(fake.resealCount == 0)
        #expect(fake.retired == 0)
    }

    @Test func aNewKeyThatCannotBeReadLocksEveryExtensionAndKeepsTheOldKey() {
        fake.state.withLock { $0.root = .unavailable }
        fake.files("github")
        let migration = fake.migration
        migration.run()
        migration.clipboardSettled(true)
        #expect(!migration.allows("github"))
        #expect(fake.resealCount == 0)
        #expect(fake.retired == 0)
    }

    @Test func eachFileMovesFromTheOldKeyToItsOwnExtensionsKey() throws {
        fake.files("GitHub", "notes")
        fake.migration.run()
        let calls = fake.state.withLock { $0.resealed }
        try #require(calls.count == 2)
        let bytes = { (key: SymmetricKey) in key.withUnsafeBytes { Data($0).base64EncodedString() } }
        #expect(calls.map { bytes($0.from) } == [Self.old, Self.old])
        #expect(bytes(calls[0].to) == StorageKey.extensionKey(root: Self.root, name: "github"))
        #expect(bytes(calls[1].to) == StorageKey.extensionKey(root: Self.root, name: "notes"))
    }

    @Test func waitingReturnsAtOnceWithoutAMoveAndOnceTheMoveIsDone() async {
        let idle = fake.migration
        let clock = ContinuousClock()
        let start = clock.now
        await idle.settled(within: .seconds(5))
        #expect(clock.now - start < .seconds(1))

        fake.files("github")
        let migration = fake.migration
        migration.begin()
        await migration.settled(within: .seconds(5))
        #expect(fake.resealCount == 1)
        #expect(migration.allows("github"))
    }

    @Test func aWaiterThatIsCancelledStopsWaitingAtOnce() async {
        let release = DispatchSemaphore(value: 0)
        let (old, root) = (Self.old, Self.root)
        let migration = StorageMigration(environment: StorageMigration.Environment(
            legacy: { .key(old) },
            root: { .key(root) },
            storageFiles: { [StorageMigration.StorageFile(name: "github", file: URL(fileURLWithPath: "/data/github/local-storage.sqlite"))] },
            reseal: { _, _, _ in
                release.wait()
                return .done(resealed: 0)
            },
            retire: {}
        ))
        defer { release.signal() }
        migration.begin()
        let clock = ContinuousClock()
        let start = clock.now
        // The limit is long and the bound loose, so a busy test run does not fail it; a waiter that ignored
        // cancellation would keep polling until the limit.
        let waiter = Task { await migration.settled(within: .seconds(30)) }
        waiter.cancel()
        await waiter.value
        #expect(clock.now - start < .seconds(20))
        #expect(!migration.allows("github"), "the move is still running")
    }

    @Test func onlyTheDataFoldersOwnStorageFilesAreFound() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("floe-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: data) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("floe-outside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        for name in ["github", "empty", "linked-file"] {
            try FileManager.default.createDirectory(at: data.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data().write(to: outside.appendingPathComponent("local-storage.sqlite"))
        try Data().write(to: data.appendingPathComponent("github/local-storage.sqlite"))
        try FileManager.default.createSymbolicLink(at: data.appendingPathComponent("linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: data.appendingPathComponent("linked-file/local-storage.sqlite"),
            withDestinationURL: outside.appendingPathComponent("local-storage.sqlite")
        )
        let found = try #require(StorageMigration.storageFiles(in: data))
        #expect(found.map(\.name) == ["github"])
        #expect(found.first?.file.lastPathComponent == "local-storage.sqlite")
    }

    @Test func aDataFolderThatCannotBeReadIsNoListAtAll() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("floe-data-\(UUID().uuidString)")
        let github = data.appendingPathComponent("github")
        try FileManager.default.createDirectory(at: github, withIntermediateDirectories: true)
        try Data().write(to: github.appendingPathComponent("local-storage.sqlite"))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: github.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: data.path)
            try? FileManager.default.removeItem(at: data)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: github.path)
        #expect(StorageMigration.storageFiles(in: data) == nil, "a folder in it that cannot be read")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: github.path)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: data.path)
        #expect(StorageMigration.storageFiles(in: data) == nil, "the data folder itself")
        #expect(StorageMigration.storageFiles(in: data.deletingLastPathComponent().appendingPathComponent("floe-never-made-\(UUID().uuidString)")) == [], "no data folder has nothing in it")
    }

    @Test func aDataFolderThatCouldNotBeReadKeepsTheOldKeyAndEveryExtensionLocked() {
        fake.state.withLock { $0.files = nil }
        let migration = fake.migration
        migration.run()
        migration.clipboardSettled(true)
        #expect(!migration.allows("github"))
        #expect(fake.retired == 0)
    }
}
