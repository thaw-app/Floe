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
}
