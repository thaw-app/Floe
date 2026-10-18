//
//  QRCodeRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// The QR code as a row owner, with its own pasteboard, a scratch Downloads folder and no Quick Look.
@MainActor
final class QRCodeRowsTests {
    private let board = NSPasteboard.withUniqueName()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-qr-\(UUID().uuidString)", isDirectory: true)
    private let asked = CallLog()
    private let rows = QRCodeRows()

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asked = asked
        rows.pasteboard = board
        rows.downloads = folder
        rows.host = RowHost(showHUD: { asked.note("hud: \($0)") }, leave: { asked.note("leave") })
        rows.preview = { asked.note("preview: \($0.pathExtension)") }
    }

    isolated deinit {
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func returnCopiesThePicture() {
        #expect(rows.returnTitle(for: .qrCode("https://example.com")) == "Copy Image")
        #expect(rows.open(.qrCode("https://example.com"), flags: []))
        #expect(board.canReadObject(forClasses: [NSImage.self]))
        #expect(asked.all == ["leave", "hud: Copied the QR code"])
    }

    @Test func returnOnTextTooLongForACodeSaysSoAndCopiesNothing() {
        rows.copyQRCode(for: String(repeating: "x", count: 5000))
        #expect(!board.canReadObject(forClasses: [NSImage.self]))
        #expect(asked.all == ["hud: That is too long for a QR code"])
    }

    @Test func theMenuShowsTheCodeInQuickLookAndSavesItUnderANewName() throws {
        let actions = try #require(rows.actions(for: .qrCode("floe")))
        #expect(actions.compactMap { $0?.title } == ["Quick Look", "Save to Downloads"])
        actions[1]?.run()
        actions[2]?.run()
        actions[2]?.run()
        let saved = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(saved == ["QR Code 2.png", "QR Code.png"])
        #expect(asked.all == ["preview: png", "leave", "hud: Saved QR Code.png", "leave", "hud: Saved QR Code 2.png"])
    }

    @Test func aRowThatIsNotAQRCodeIsLeftToOthers() {
        #expect(!rows.open(.emojiSearch, flags: []))
        #expect(rows.actions(for: .emojiSearch) == nil)
        #expect(rows.returnTitle(for: .emojiSearch) == nil)
    }
}
