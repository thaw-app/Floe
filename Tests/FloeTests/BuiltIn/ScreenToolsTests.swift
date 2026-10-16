//
//  ScreenToolsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing
import Vision

@MainActor struct ScreenToolsTests {
    /// Black text on white, large enough to be read without doubt.
    private func picture(of text: String) throws -> CGImage {
        let size = NSSize(width: 900, height: 200)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 40, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.cgImage)
    }

    /// Whether Vision itself finds text in a picture, asked off the main thread as Floe asks it.
    @concurrent
    private static func visionReadsText(in image: CGImage) async -> Bool {
        await !((try? RecognizeTextRequest().perform(on: image)) ?? []).isEmpty
    }

    // MARK: Color

    @Test func aColorIsWrittenAsItsHexInSRGB() {
        #expect(ScreenTools.hex(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) == "#FF8000")
        #expect(ScreenTools.hex(.black) == "#000000")
        #expect(ScreenTools.hex(NSColor(srgbRed: 0.631, green: 0.698, blue: 0.765, alpha: 0.2)) == "#A1B2C3", "the alpha is not part of it")
    }

    // MARK: QR codes

    @Test func aCodeMadeFromATextReadsBackAsThatText() async throws {
        let text = "https://github.com/thaw-app/Floe?ref=qr&x=ñ"
        let image = try #require(ScreenTools.qrCode(for: text))
        #expect(image.width == image.height)
        #expect(image.width >= 300)
        let reading = await ScreenTools.read(image)
        #expect(reading.codes == [text])
        #expect(ScreenTools.copied(from: reading)?.text == text)
        #expect(ScreenTools.copied(from: reading)?.line == "Copied what the code says")
        #expect(ScreenTools.png(image)?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func aTextTooLongForACodeMakesNone() {
        #expect(ScreenTools.qrCode(for: String(repeating: "x", count: 5000)) == nil)
    }

    // MARK: Text

    @Test func textInAPictureIsReadAndAPictureWithNoneGivesNothing() async throws {
        let image = try picture(of: "Floe reads 2026")
        // Vision has no text model on some machines, such as the virtual ones CI runs on; there is nothing to check there.
        guard await Self.visionReadsText(in: image) else {
            try Test.cancel("Vision cannot read text on this machine")
        }
        let reading = await ScreenTools.read(image)
        #expect(reading.text == "Floe reads 2026")
        #expect(reading.codes.isEmpty)
        #expect(ScreenTools.copied(from: reading)?.line == "Copied the text")
        let blank = try await ScreenTools.read(picture(of: ""))
        #expect(blank == ScreenReading())
        #expect(ScreenTools.copied(from: blank) == nil)
    }

    @Test func aCodeIsCopiedBeforeTheTextAroundIt() {
        let both = ScreenReading(codes: ["https://example.com", "second"], text: "Scan me")
        #expect(ScreenTools.copied(from: both)?.text == "https://example.com\nsecond")
    }

    // MARK: The row

    @Test func theQRRowAnswersToItsWordAndIsSavedUnderANameOfItsOwn() throws {
        let provider = QRCodeSearchProvider()
        #expect(provider.contribution(for: SearchContext(query: "qr")).pinned.isEmpty)
        #expect(provider.contribution(for: SearchContext(query: "qrcode hello")).pinned.isEmpty)
        let row = try #require(provider.contribution(for: SearchContext(query: "qr hello there")).pinned.first?.item)
        #expect(row.title == "QR Code for hello there")
        #expect(row.id == "qr-code", "the id never holds the text")
        #expect(row.kind == "QR Code")
        #expect(row.isScopeResult)
        #expect(QRCodeRows().returnTitle(for: row) == "Copy Image")

        let defaults = MemoryDefaults()
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-qr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(model.features.qrCodes.writeQRCode(for: "hello", to: folder)?.lastPathComponent == "QR Code.png")
        #expect(model.features.qrCodes.writeQRCode(for: "hello", to: folder)?.lastPathComponent == "QR Code 2.png")
        #expect(model.features.qrCodes.writeQRCode(for: String(repeating: "x", count: 5000), to: folder) == nil)
        #expect(model.features.qrCodes.qrCodeActions(for: "hello").compactMap { $0?.title } == ["Quick Look", "Save to Downloads"])
    }

    @Test func theScreenCommandsAreSystemCommandsFoundByTheirWords() {
        #expect(SystemCommand.pickColor.title == "Pick Color from Screen")
        #expect(SystemCommand.copyScreenText.title == "Copy Text from Screen")
        #expect(SystemCommand.pickColor.keywords.contains("eyedropper"))
        #expect(SystemCommand.copyScreenText.keywords.contains("ocr"))
        #expect(SystemCommand.pickColor.confirmation == nil)
    }
}
