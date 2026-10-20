//
//  SearchFieldShapeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing
import ThawUI

struct SearchFieldShapeTests {
    @Test func eachShapeHasItsCorner() {
        #expect(SearchFieldShape.rounded.cornerRadius(height: 44) == ThawRadius.control)
        #expect(SearchFieldShape.capsule.cornerRadius(height: 44) == 22)
        #expect(SearchFieldShape.square.cornerRadius(height: 44) == 0)
    }

    @Test func theOutlineFillsItsRectAndInsets() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 44)
        for shape in SearchFieldShape.allCases {
            #expect(shape.outline.path(in: rect).boundingRect == rect)
            #expect(shape.outline.inset(by: 2).path(in: rect).boundingRect == rect.insetBy(dx: 2, dy: 2))
        }
    }

    @Test func theShapeIsRoundedUntilChosenAndIsStored() {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.searchFieldShape == .rounded)
        settings.searchFieldShape = .capsule
        settings.save()
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).searchFieldShape == .capsule)
    }

    @Test func theSettingsSearchFindsThePicker() {
        let entry = SearchIndex.appearanceEntries.first { $0.id.hasSuffix("searchFieldShape") }
        #expect(entry?.section == "Layout")
    }

    // MARK: The beam

    @Test func theBeamIsColorfulUntilChosenAndIsStored() {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.searchFieldBeam == .colorful)
        #expect(settings.searchFieldBeamFrameRate == 60)
        settings.searchFieldBeam = .off
        settings.searchFieldBeamFrameRate = 30
        settings.save()
        let reread = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(reread.searchFieldBeam == .off)
        #expect(reread.searchFieldBeamFrameRate == 30)
        #expect(SearchIndex.appearanceEntries.first { $0.id.hasSuffix("searchFieldBeam") }?.section == "Layout")
    }

    @Test func everyBeamPutsColourOnAllFourSidesAndOffNone() {
        for beam in SearchFieldBeam.allCases where beam != .off {
            let places = beam.blobs.map(\.center)
            #expect(places.contains { $0.y == 0 }, "\(beam) lights the top")
            #expect(places.contains { $0.y == 1 }, "\(beam) lights the bottom")
            #expect(places.contains { $0.x == 0 }, "\(beam) lights the left")
            #expect(places.contains { $0.x == 1 }, "\(beam) lights the right")
        }
        #expect(SearchFieldBeam.off.blobs.isEmpty)
        for beam in SearchFieldBeam.allCases where beam != .off {
            #expect(beam.ring.first == beam.ring.last, "\(beam)'s colours meet without a seam round the field")
        }
        #expect(SearchFieldBeam.off.ring.isEmpty)
    }
}
