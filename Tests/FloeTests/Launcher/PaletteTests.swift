//
//  PaletteTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import SwiftUI
import Testing

struct PaletteTests {
    /// The red component the color has when drawn under the named appearance.
    private func red(_ color: Color?, under name: NSAppearance.Name) throws -> CGFloat {
        let drawn = try NSColor(#require(color))
        var red: CGFloat = -1
        try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
            red = drawn.usingColorSpace(.sRGB)?.redComponent ?? -1
        }
        return red
    }

    @Test func aDynamicColorFollowsTheAppearanceItIsDrawnIn() throws {
        let color = Palette.color(["light": "#FF0000", "dark": "#000000"])
        #expect(try red(color, under: .aqua) == 1)
        #expect(try red(color, under: .darkAqua) == 0)
    }

    @Test func aDynamicColorMayUseRaycastsNamedColors() {
        #expect(Palette.color(["light": "color:Red", "dark": "#00FF00", "adjustContrast": false]) != nil)
    }

    @Test func aDynamicColorWithoutBothSidesIsNoColor() {
        #expect(Palette.color(["light": "#FF0000"]) == nil)
        #expect(Palette.color(["light": "#FF0000", "dark": "nonsense"]) == nil)
    }

    @Test func hexAndNamedColorsStillRead() throws {
        #expect(try red(Palette.color("#FF0000"), under: .darkAqua) == 1)
        #expect(Palette.color("color:Blue") == .blue)
        #expect(Palette.color("color:Magenta") == .pink)
        #expect(Palette.color("color:NoSuchColor") == nil)
        #expect(Palette.color(7) == nil)
    }
}
