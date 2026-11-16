//
//  ClipboardSealTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import CryptoKit
@testable import Floe
import Foundation
import Synchronization
import Testing

/// The clipboard folder sealed with the storage key: unreadable in its files, whole wherever Floe reads it.
/// Serialized: the readable copies share one folder, which a test clears.
@MainActor
@Suite(.serialized)
struct ClipboardSealTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-seal-\(UUID().uuidString)")
    private let seal = ClipboardSeal(key: SymmetricKey(data: Data(repeating: 7, count: 32)))

    private func onDisk(_ name: String) -> Data? {
        try? Data(contentsOf: folder.appendingPathComponent(name))
    }

    /// A 2 by 2 PNG.
    private func png() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func whatIsWrittenIsSealedOnDiskAndReadsBackWhole() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = ClipboardFiles.onDisk(folder, seal: seal)
        try files.write(Data("my password is hunter2".utf8), "history.json", true)
        let stored = try #require(onDisk("history.json"))
        #expect(String(bytes: stored, encoding: .utf8)?.contains("hunter2") != true)
        #expect(files.read("history.json") == Data("my password is hunter2".utf8))
    }

    @Test func plainFilesFromBeforeAreSealedWhenTheFolderLoads() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("copied before".utf8).write(to: folder.appendingPathComponent("history.json"))
        let files = ClipboardFiles.onDisk(folder, seal: seal)
        _ = files.sizes()
        #expect(onDisk("history.json") != Data("copied before".utf8))
        #expect(files.read("history.json") == Data("copied before".utf8))
    }

    @Test func aSealedFileWithoutItsKeyIsUnreadableNotItsCiphertext() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try ClipboardFiles.onDisk(folder, seal: seal).write(Data("secret".utf8), "history.json", true)
        let other = ClipboardSeal(key: SymmetricKey(data: Data(repeating: 9, count: 32)))
        #expect(ClipboardFiles.onDisk(folder, seal: other).read("history.json") == nil)
        #expect(ClipboardFiles.onDisk(folder, seal: ClipboardSeal(key: nil)).read("history.json") == nil)
    }

    @Test func aSealedImagePastesAndPreviews() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try png()
        try ClipboardFiles.onDisk(folder, seal: seal).write(image, "picture.png", false)
        #expect(ClipboardHistoryStore.storedFile("picture.png", in: folder, seal: seal) == image)
        let preview = await ClipboardHistoryStore.preview(of: folder.appendingPathComponent("picture.png"), maxPixels: 16, seal: seal)
        #expect(preview.image != nil)
    }

    @Test func anExtensionGetsAnImagePathItCanRead() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try png()
        try ClipboardFiles.onDisk(folder, seal: seal).write(image, "picture.png", false)
        let entry = ClipboardEntry(id: UUID(), kind: .image, text: "", imageFile: "picture.png", date: Date(), pinned: false, sourceApp: nil)
        let copy = PasteboardContent.copy(offset: 0, in: [entry], directory: folder, seal: seal)
        let path = try #require(copy["file"])
        #expect(FileManager.default.contents(atPath: path) == image)
        #expect(!path.hasPrefix(folder.path), "the sealed file stays as it is")
    }

    @Test func withoutItsKeyNothingIsWrittenSoNothingSealedIsLostOrSavedPlainly() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try ClipboardFiles.onDisk(folder, seal: seal).write(Data("kept".utf8), "history.json", true)
        let before = onDisk("history.json")
        let locked = ClipboardFiles.onDisk(folder, seal: .unavailable)
        _ = locked.sizes()
        #expect(locked.read("history.json") == nil)
        #expect(throws: (any Error).self) { try locked.write(Data("new".utf8), "history.json", true) }
        #expect(onDisk("history.json") == before)
    }

    @Test func aLinkInTheFolderIsNotSealedIntoAFileOfItsOwn() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("floe-outside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.format"), withDestinationURL: outside)
        _ = ClipboardFiles.onDisk(folder, seal: seal).sizes()
        let link = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("link.format").path)
        #expect(link[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(ClipboardHistoryStore.storedFile("link.format", in: folder, seal: seal) == nil)
        #expect(FileManager.default.contents(atPath: outside.path) == Data("outside".utf8))
    }

    /// A seal that changes, as the keychain may between launch and a later copy.
    private nonisolated final class Changing: @unchecked Sendable {
        var seal: ClipboardSeal
        init(_ seal: ClipboardSeal) {
            self.seal = seal
        }
    }

    @Test func aFolderThatLoadedLockedStaysLockedSoItsHistoryIsNotOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try ClipboardFiles.onDisk(folder, seal: seal).write(Data("pinned entries".utf8), "history.json", true)
        let before = onDisk("history.json")
        let changing = Changing(.unavailable)
        let files = ClipboardFiles.onDisk(folder, seal: changing.seal)
        _ = files.sizes()
        #expect(files.read("history.json") == nil)
        changing.seal = seal
        #expect(throws: (any Error).self) { try files.write(Data("one new copy".utf8), "history.json", true) }
        #expect(onDisk("history.json") == before, "the history it could not read comes back at the next launch")
    }

    @Test func theSixLatestImagesAnExtensionReadStayReadableAndClearingRemovesThem() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        PasteboardContent.removeReadableCopies()
        let image = try png()
        let files = ClipboardFiles.onDisk(folder, seal: seal)
        var copies: [URL] = []
        for number in 0 ..< 7 {
            try files.write(image, "\(number).png", false)
            copies.append(try #require(PasteboardContent.readableCopy(of: "\(number).png", in: folder, seal: seal)))
        }
        #expect(!FileManager.default.fileExists(atPath: copies[0].path), "Raycast reads back five copies and the current one")
        #expect(copies.dropFirst().allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        PasteboardContent.removeReadableCopies()
        #expect(!copies.contains { FileManager.default.fileExists(atPath: $0.path) })
    }

    // MARK: The move off the old storage key

    private let old = SymmetricKey(data: Data(repeating: 9, count: 32))

    /// What the folder told the migration, as it loaded.
    private nonisolated final class Answers: Sendable {
        let given = Mutex<[Bool]>([])
        func note(_ done: Bool) {
            given.withLock { $0.append(done) }
        }
    }

    @Test func aFileSealedWithTheOldKeyOpensWhileTheOldKeyIsKept() throws {
        let sealed = try ClipboardSeal(key: old).seal(Data("from before".utf8), name: "history.json")
        let moving = ClipboardSeal(key: seal.key, legacy: old)
        #expect(moving.open(sealed, name: "history.json") == Data("from before".utf8))
        #expect(seal.open(sealed, name: "history.json") == nil)
    }

    @Test func filesSealedWithTheOldKeyAreSealedAgainWithTheNewOneAsTheFolderLoads() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stranger = ClipboardSeal(key: SymmetricKey(data: Data(repeating: 4, count: 32)))
        try ClipboardSeal(key: old).seal(Data("from before".utf8), name: "history.json").write(to: folder.appendingPathComponent("history.json"))
        let unknown = try stranger.seal(Data("someone else's".utf8), name: "other.png")
        try unknown.write(to: folder.appendingPathComponent("other.png"))
        try Data("plain".utf8).write(to: folder.appendingPathComponent("plain.txt"))
        let moving = ClipboardSeal(key: seal.key, legacy: old)
        let answers = Answers()
        _ = ClipboardFiles.onDisk(folder, seal: moving, settled: answers.note).sizes()
        let current = ClipboardFiles.onDisk(folder, seal: seal, settled: { _ in /* not asked */ })
        #expect(current.read("history.json") == Data("from before".utf8))
        #expect(current.read("plain.txt") == Data("plain".utf8))
        #expect(onDisk("plain.txt") != Data("plain".utf8))
        #expect(onDisk("other.png") == unknown, "a file that opens with neither key is left as it is")
        #expect(answers.given.withLock { $0 } == [true])
    }

    @Test func aLockedFolderMovesNothingAndSaysItIsNotDone() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sealed = try ClipboardSeal(key: old).seal(Data("from before".utf8), name: "history.json")
        try sealed.write(to: folder.appendingPathComponent("history.json"))
        let answers = Answers()
        _ = ClipboardFiles.onDisk(folder, seal: .unavailable, settled: answers.note).sizes()
        #expect(onDisk("history.json") == sealed)
        #expect(answers.given.withLock { $0 } == [false])
    }

    @Test func aReadableCopyFolderLeftWithWiderPermissionsIsMadePrivate() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        PasteboardContent.removeReadableCopies()
        defer { PasteboardContent.removeReadableCopies() }
        let readable = FileManager.default.temporaryDirectory.appendingPathComponent("Floe Clipboard")
        try FileManager.default.createDirectory(at: readable, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try ClipboardFiles.onDisk(folder, seal: seal).write(try png(), "picture.png", false)
        _ = try #require(PasteboardContent.readableCopy(of: "picture.png", in: folder, seal: seal))
        let permissions = try FileManager.default.attributesOfItem(atPath: readable.path)[.posixPermissions] as? Int
        #expect(permissions == 0o700)
    }

    @Test func anImageLeavingTheHistoryTakesItsReadableCopyWithIt() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        PasteboardContent.removeReadableCopies()
        let store = ClipboardHistoryStore(files: .onDisk(folder, seal: seal), limits: .init(maxEntries: 2), monitorsPasteboard: false)
        let date = Date(timeIntervalSince1970: 1)
        store.record(ClipboardCapture(content: .image(try png(), fallbackText: nil), date: date, sourceApp: "Tests"))
        store.flush()
        let name = try #require(store.entries.first?.imageFile)
        let deleted = try #require(PasteboardContent.readableCopy(of: name, in: folder, seal: seal))
        store.delete(store.entries[0])
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: deleted.path), "deleted")

        store.record(ClipboardCapture(content: .image(try png(), fallbackText: nil), date: date, sourceApp: "Tests"))
        store.flush()
        let oldest = try #require(store.entries.first?.imageFile)
        let evicted = try #require(PasteboardContent.readableCopy(of: oldest, in: folder, seal: seal))
        store.record(ClipboardCapture(content: .text("one"), date: date.addingTimeInterval(1), sourceApp: "Tests"))
        store.record(ClipboardCapture(content: .text("two"), date: date.addingTimeInterval(2), sourceApp: "Tests"))
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: evicted.path), "past the history's limit")
    }
}
