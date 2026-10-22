//
//  SearchFieldShapeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import QuartzCore
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

    @Test func everyBeamHasItsOwnNameAndID() {
        let beams = SearchFieldBeam.allCases
        #expect(beams.map(\.title) == ["Off", "Colorful", "Mono", "Ocean", "Sunset"])
        #expect(Set(beams.map(\.id)).count == beams.count)
        #expect(beams.allSatisfy { $0.id == $0.rawValue })
    }

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

    @Test(arguments: [Float(15), 30, 45, 60, 75, 90, 105, 120])
    func theBeamInterpolatesAndClosesItsLoop(frameRate: Float) throws {
        let spin = try #require(BeamLayerView.spin(at: frameRate, in: CGSize(width: 680, height: 44)) as? CAKeyframeAnimation)
        let angles = try #require(spin.values as? [Double])
        #expect(spin.calculationMode == .linear)
        #expect(spin.keyTimes?.count == angles.count)
        #expect(spin.keyTimes?.first == 0)
        #expect(spin.keyTimes?.last == 1)
        #expect(spin.preferredFrameRateRange.preferred == frameRate)
        #expect(spin.duration == SearchFieldBeamView<Rectangle>.turn)
        let first = try #require(angles.first)
        let last = try #require(angles.last)
        #expect(abs(last - first - 2 * .pi) < 1e-9, "the loop closes with one full turn, without a missing last frame")
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(first + BeamLight.glintCenter * 2 * .pi) < 1e-9, "the bright spot starts at the border path's origin")

        let drift = try #require(BeamLayerView.drift(at: frameRate) as? CAKeyframeAnimation)
        let opacities = try #require(drift.values as? [Double])
        #expect(drift.calculationMode == .linear)
        #expect(drift.keyTimes?.count == opacities.count)
        #expect(drift.preferredFrameRateRange.preferred == frameRate)
        #expect(opacities.first == 0)
        #expect(opacities.last == 0)
        #expect(opacities.allSatisfy { (0 ... 1).contains($0) })
        #expect(abs(opacities[opacities.count / 2] - 1) < 1e-9, "fully in halfway through, then back out")
    }

    @Test func rebuildingOrChangingFrameRateKeepsTheSameClockAndCurve() throws {
        let field = CGSize(width: 680, height: 44)
        let edge = try #require(BeamLayerView.spin(at: 60, in: field) as? CAKeyframeAnimation)
        let spill = try #require(BeamLayerView.spin(at: 30, in: field) as? CAKeyframeAnimation)
        let drift = BeamLayerView.drift(at: 60)
        #expect(edge.beginTime > 0)
        #expect(edge.beginTime == spill.beginTime)
        #expect(edge.beginTime == drift.beginTime)
        #expect(edge.timeOffset == spill.timeOffset)
        #expect(edge.values as? [Double] == spill.values as? [Double])
        #expect(drift.timeOffset == SearchFieldBeamView<Rectangle>.drift.period / 4)
    }

    @Test func theGlintAndBloomPeakAtTheSamePlace() throws {
        let glint = try #require(BeamLight.glint.max { $0.1 < $1.1 })
        let bloom = try #require(BeamLight.bloom.max { $0.1 < $1.1 })
        #expect(glint.0 == BeamLight.glintCenter)
        #expect(bloom.0 == glint.0)
    }

    @Test func theLightKeepsOneSpeedAlongTheBorder() throws {
        let field = CGSize(width: 680, height: 44)
        #expect(BeamLayerView.angle(along: 0, of: field) == 0)
        #expect(abs(BeamLayerView.angle(along: 0.5, of: field) - .pi) < 1e-9, "halfway round is the left side's middle")
        #expect(abs(BeamLayerView.angle(along: 0.25, of: field) - .pi / 2) < 1e-9, "a quarter round is the top's middle")
        let turn = (0 ..< 400).map { BeamLayerView.angle(along: Double($0) / 400, of: field) }
        #expect(zip(turn, turn.dropFirst()).allSatisfy { $0 < $1 }, "the angle only grows")
        #expect(try #require(turn.last) < 2 * .pi)
        // The top right corner is 22 points of the 1,448 round the border away from the start.
        #expect(abs(BeamLayerView.angle(along: 22.0 / 1448, of: field) - atan2(22, 340)) < 1e-9)
    }
}
