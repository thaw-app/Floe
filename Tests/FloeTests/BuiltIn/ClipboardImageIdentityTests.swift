//
//  ClipboardImageIdentityTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing

/// How the history tells one copied image from another: by the whole PNG, never by how it starts.
@MainActor
@Suite("Clipboard image identity", .serialized)
struct ClipboardImageIdentityTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FloeClipboardIdentity-\(UUID().uuidString)", isDirectory: true)

    @Test func twoImagesThatStartAlikeAreTwoImages() {
        let start = Data(repeating: 7, count: 64)
        let first = ClipboardEntry.image(named: "a.png", png: start + Data([1]), date: .now, sourceApp: nil)
        let second = ClipboardEntry.image(named: "b.png", png: start + Data([2]), date: .now, sourceApp: nil)
        let again = ClipboardEntry.image(named: "c.png", png: start + Data([1]), date: .now, sourceApp: nil)
        #expect(first.identity != second.identity)
        #expect(first.identity == again.identity)
        #expect(!first.hasEarlierImageIdentity)
    }

    @Test func anImageSavedByAnEarlierFloeMergesWithANewCopyOfItAndKeepsItsPin() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copied = try png()
        let stored = try #require(ClipboardHistoryStore.storedPNG(copied))
        try stored.write(to: directory.appendingPathComponent("kept.png"))
        // An earlier Floe kept only the start of the PNG, base64, as the entry's text.
        let saved = """
        [{"id":"22222222-2222-2222-2222-222222222222","kind":"image","text":"\(stored.prefix(64).base64EncodedString())",\
        "imageFile":"kept.png","date":769999000,"pinned":true}]
        """
        try Data(saved.utf8).write(to: directory.appendingPathComponent(ClipboardFiles.historyName))

        let store = ClipboardHistoryStore(
            files: .onDisk(directory), limits: .init(maxEntries: 300, maxBytes: .max, maxQueuedBytes: .max), monitorsPasteboard: false,
            storedPNG: ClipboardHistoryStore.storedPNG
        )
        store.flush()
        #expect(store.entries.first?.text == ClipboardEntry.imageIdentity(of: stored), "the earlier entry is hashed from its file")
        store.record(ClipboardCapture(content: .image(copied, fallbackText: nil), date: Date(timeIntervalSince1970: 800_000_000), sourceApp: "Tests"))
        store.flush()
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.id.uuidString == "22222222-2222-2222-2222-222222222222")
        #expect(store.entries.first?.pinned == true)
    }

    /// Noise, so the PNG has a real size.
    private func png() throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 32 * 4, bitsPerPixel: 32
        ))
        let pixels = try #require(rep.bitmapData)
        for offset in 0 ..< 32 * 32 * 4 {
            pixels[offset] = offset % 4 == 3 ? 255 : UInt8.random(in: 0 ... 255)
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
