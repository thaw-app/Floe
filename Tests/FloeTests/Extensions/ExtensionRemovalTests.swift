//
//  ExtensionRemovalTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ExtensionRemovalTests {
    @Test func onlyAFolderOfFloeOrRaycastCanBeRemoved() {
        let floe = URL(fileURLWithPath: "/floe-tests/floe/Extensions")
        let raycast = URL(fileURLWithPath: "/floe-tests/raycast/extensions")
        let roots = [floe, raycast]
        #expect(ExtensionStore.canRemove(floe.appendingPathComponent("notes"), roots: roots))
        #expect(ExtensionStore.canRemove(raycast.appendingPathComponent("0b1c/../0b1c"), roots: roots))
        #expect(!ExtensionStore.canRemove(URL(fileURLWithPath: "/floe-tests/checkout/extensions/sample"), roots: roots))
        #expect(!ExtensionStore.canRemove(floe.appendingPathComponent("notes/inner"), roots: roots))
        #expect(!ExtensionStore.canRemove(floe, roots: roots))
    }

    @MainActor @Test func removingAFolderOutsideFloeTrashesItUnderTheGivenName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-raycast-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("0b1c2d")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExtensionStore()
        var reloads = 0
        store.onInstalled = { reloads += 1 }
        var receipts: [Receipt] = []
        store.remove(folder: folder, named: "spotify-player") { receipts.append($0) }
        defer { receipts.compactMap(\.trashed).forEach { try? FileManager.default.removeItem(atPath: $0) } }
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(receipts.map(\.subject) == ["spotify-player"])
        #expect(receipts.first?.kind == .extensionRemoved)
        #expect(reloads == 1)
        #expect(store.error == nil)
    }
}
