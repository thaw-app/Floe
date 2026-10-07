//
//  MenuBarGlyphTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct MenuBarGlyphTests {
    /// How opaque the glyph is at a point given in the app icon's 1024 point space, drawn large enough to read.
    private func alpha(atIconPoint point: CGPoint) throws -> CGFloat {
        let side: CGFloat = 180
        let image = MenuBarGlyph.image(side: side)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let scale = (side - 20) / 528
        let x = side / 2 + (point.x - 498) * scale
        let y = side / 2 + (point.y - 471.5) * scale
        return try #require(bitmap.colorAt(x: Int(x), y: Int(y))).alphaComponent
    }

    @Test func itIsATemplateTheMenuBarTints() {
        let image = MenuBarGlyph.image()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.accessibilityDescription == "Floe")
    }

    @Test func theFloeIsSolidTheLeadIsOpenAndTheShardIsItsOwnPiece() throws {
        #expect(try alpha(atIconPoint: CGPoint(x: 420, y: 520)) > 0.9, "the body of the floe")
        #expect(try alpha(atIconPoint: CGPoint(x: 660, y: 340)) > 0.9, "the shard")
        #expect(try alpha(atIconPoint: CGPoint(x: 592, y: 476)) < 0.1, "the lead between them")
        #expect(try alpha(atIconPoint: CGPoint(x: 250, y: 240)) < 0.1, "outside the floe")
    }
}
