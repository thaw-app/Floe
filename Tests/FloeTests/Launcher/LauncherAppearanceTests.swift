//
//  LauncherAppearanceTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing

struct LauncherAppearanceTests {
    private static let side = 20
    private static let red = StoredColor(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))
    private static let blue = StoredColor(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))

    /// The style painted over a clear square, as premultiplied sRGB bytes, top row first.
    private func painted(_ style: AnyShapeStyle) throws -> [UInt8] {
        let side = Self.side
        let renderer = ImageRenderer(content: Rectangle().fill(style).frame(width: CGFloat(side), height: CGFloat(side)))
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let alpha = CGImageAlphaInfo.premultipliedLast.rawValue
            let context = try #require(CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space, bitmapInfo: alpha))
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return bytes
    }

    private func pixel(_ bytes: [UInt8], x: Int, y: Int) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let at = (y * Self.side + x) * 4
        return (Int(bytes[at]), Int(bytes[at + 1]), Int(bytes[at + 2]), Int(bytes[at + 3]))
    }

    private func isClose(_ a: StoredColor, _ b: StoredColor) -> Bool {
        abs(a.red - b.red) < 0.001 && abs(a.green - b.green) < 0.001 && abs(a.blue - b.blue) < 0.001 && abs(a.opacity - b.opacity) < 0.001
    }

    @Test func aStoredColorIsOpaqueBlackUntilSet() {
        let color = StoredColor()
        #expect(color.red == 0)
        #expect(color.green == 0)
        #expect(color.blue == 0)
        #expect(color.opacity == 1)
    }

    @Test func aStoredColorKeepsTheSRGBComponentsOfItsColor() {
        let stored = StoredColor(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.5))
        var expected = StoredColor()
        expected.red = 0.2
        expected.green = 0.4
        expected.blue = 0.6
        expected.opacity = 0.5
        #expect(isClose(stored, expected))
    }

    @Test func aColorFromAnotherSpaceIsStoredAsItsSRGBEquivalent() throws {
        let stored = StoredColor(Color(.displayP3, red: 0.5, green: 0.25, blue: 0.75, opacity: 1))
        let converted = try #require(NSColor(displayP3Red: 0.5, green: 0.25, blue: 0.75, alpha: 1).usingColorSpace(.sRGB))
        var expected = StoredColor()
        expected.red = Double(converted.redComponent)
        expected.green = Double(converted.greenComponent)
        expected.blue = Double(converted.blueComponent)
        #expect(isClose(stored, expected))
        #expect(abs(stored.red - 0.5) > 0.01, "the Display P3 numbers are not kept as they are")
    }

    @Test func aStoredColorGivesBackTheColorItWasMadeFrom() {
        let stored = StoredColor(Color(.sRGB, red: 0.07, green: 0.4, blue: 0.9, opacity: 0.35))
        #expect(isClose(StoredColor(stored.color), stored))
    }

    @Test func aStoredColorIsSavedAsFourNamedNumbers() throws {
        let json = #"{"red":0.25,"green":0.5,"blue":0.75,"opacity":0.5}"#
        let decoded = try JSONDecoder().decode(StoredColor.self, from: Data(json.utf8))
        #expect(decoded.red == 0.25)
        #expect(decoded.green == 0.5)
        #expect(decoded.blue == 0.75)
        #expect(decoded.opacity == 0.5)

        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Double]
        #expect(saved == ["red": 0.25, "green": 0.5, "blue": 0.75, "opacity": 0.5])
    }

    @Test(arguments: [(LauncherTintKind.none, "none", "None"), (.solid, "solid", "Solid"), (.gradient, "gradient", "Gradient")])
    func aTintKindIsStoredByNameAndShownByTitle(kind: LauncherTintKind, stored: String, title: String) {
        #expect(kind.rawValue == stored)
        #expect(kind.id == stored)
        #expect(kind.title == title)
        #expect(LauncherTintKind(rawValue: stored) == kind)
    }

    @Test func theTintKindsAreListedInPickerOrder() {
        #expect(LauncherTintKind.allCases == [.none, .solid, .gradient])
    }

    @Test func theStartingPaletteIsTheAppIconsBlue() {
        let bright = StoredColor(Color(red: 0.07, green: 0.40, blue: 0.90))
        let navy = StoredColor(Color(red: 0.02, green: 0.10, blue: 0.40))
        let tint = LauncherTint()
        #expect(tint.kind == .none)
        #expect(tint.opacity == 0.35)
        #expect(tint.solid == bright)
        #expect(tint.gradient.start == bright)
        #expect(tint.gradient.end == navy)
        #expect(tint.gradient.angle == 180)
    }

    @Test func theStartingBorderIsAThinTranslucentWhiteLine() {
        let border = LauncherBorder()
        #expect(border.width == 1)
        #expect(isClose(border.color, StoredColor(Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.6))))
    }

    @Test func aTintAndABorderSurviveBeingSaved() throws {
        let tint = LauncherTint(kind: .gradient, solid: Self.red, gradient: LauncherGradient(start: Self.red, end: Self.blue, angle: 45), opacity: 0.7)
        let border = LauncherBorder(color: Self.blue, width: 3)
        #expect(try JSONDecoder().decode(LauncherTint.self, from: JSONEncoder().encode(tint)) == tint)
        #expect(try JSONDecoder().decode(LauncherBorder.self, from: JSONEncoder().encode(border)) == border)
    }

    @Test func noTintDrawsNothing() {
        #expect(LauncherTint(kind: .none).backgroundStyle == nil)
    }

    @Test func aSolidTintIsItsColorAtTheTintsOpacity() throws {
        let style = try #require(LauncherTint(kind: .solid, solid: Self.red, opacity: 0.5).backgroundStyle)
        let middle = try pixel(painted(style), x: 10, y: 10)
        #expect(abs(middle.alpha - 128) <= 2)
        #expect(abs(middle.red - 128) <= 2)
        #expect(middle.green == 0)
        #expect(middle.blue == 0)
    }

    @Test func aGradientTintIsItsGradientAtTheTintsOpacity() throws {
        let gradient = LauncherGradient(start: Self.red, end: Self.blue, angle: 0)
        let style = try #require(LauncherTint(kind: .gradient, gradient: gradient, opacity: 0.5).backgroundStyle)
        let bytes = try painted(style)
        let top = pixel(bytes, x: 10, y: 0)
        let bottom = pixel(bytes, x: 10, y: 19)
        #expect(abs(top.alpha - 128) <= 2)
        #expect(abs(bottom.alpha - 128) <= 2)
        #expect(top.red > top.blue)
        #expect(bottom.blue > bottom.red)
    }

    /// 0 starts at the top, 90 at the left, 180 at the bottom, 270 at the right.
    @Test(arguments: [(0.0, 10, 0), (90.0, 0, 10), (180.0, 10, 19), (270.0, 19, 10)])
    func aGradientStartsOnTheSideItsAngleNames(angle: Double, x: Int, y: Int) throws {
        let bytes = try painted(LauncherGradient(start: Self.red, end: Self.blue, angle: angle).style)
        let start = pixel(bytes, x: x, y: y)
        let end = pixel(bytes, x: Self.side - 1 - x, y: Self.side - 1 - y)
        #expect(start.red > 200)
        #expect(start.blue < 60)
        #expect(end.blue > 200)
        #expect(end.red < 60)
    }

    @Test func theDefaultColoursStayTheAppIconsBlueAndNavy() {
        let blue = StoredColor(Color(red: 0.07, green: 0.40, blue: 0.90))
        let navy = StoredColor(Color(red: 0.02, green: 0.10, blue: 0.40))
        #expect(LauncherGradient().start == blue)
        #expect(LauncherGradient().end == navy)
        #expect(LauncherTint().solid == blue)
        #expect(LauncherGlass().color == blue)
    }
}
