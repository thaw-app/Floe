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
    func theBeamRunsOneLapAndDrifts(frameRate: Float) throws {
        let lap = try #require(BeamLayerView.run(from: 0.3, along: 1000, at: frameRate) as? CABasicAnimation)
        #expect(lap.keyPath == "lineDashPhase")
        #expect(lap.fromValue as? CGFloat == -300)
        #expect(lap.toValue as? CGFloat == -1300, "one lap of the border, so the loop closes without a jump")
        #expect(lap.timingFunction == CAMediaTimingFunction(name: .linear), "one speed all the way round")
        #expect(lap.preferredFrameRateRange.preferred == frameRate)
        #expect(lap.duration == SearchFieldBeamView<Rectangle>.turn)

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

    @Test func rebuildingOrChangingFrameRateKeepsTheSameClock() {
        let edge = BeamLayerView.run(from: 0, along: 800, at: 60)
        let spill = BeamLayerView.run(from: 0, along: 800, at: 30)
        let drift = BeamLayerView.drift(at: 60)
        #expect(edge.beginTime > 0)
        #expect(edge.beginTime == spill.beginTime)
        #expect(edge.beginTime == drift.beginTime)
        #expect(drift.timeOffset == SearchFieldBeamView<Rectangle>.drift.period / 4)
    }

    @Test func theGlintAndBloomPeakAtTheSamePlace() throws {
        let glint = try #require(BeamLight.glint.max { $0.1 < $1.1 })
        let bloom = try #require(BeamLight.bloom.max { $0.1 < $1.1 })
        #expect(glint.0 == BeamLight.glintCenter)
        #expect(bloom.0 == glint.0)
    }

    @Test func theLightsStretchesNestAndAddUpToItsLevel() throws {
        for stops in [BeamLight.hairlineWindow, BeamLight.glowWindow, BeamLight.glint, BeamLight.bloom] {
            let bands = BeamLayerView.bands(stops)
            #expect(!bands.isEmpty)
            #expect(zip(bands, bands.dropFirst()).allSatisfy { $0.from <= $1.from && $0.to >= $1.to }, "each stretch lies inside the fainter one")
            let peak = try #require(stops.map(\.1).max())
            let shown = bands.reduce(0.0) { $0 + $1.alpha * (1 - $0) }
            // A peak that is a single point has no stretch of its own, so the light stops one level short of it.
            #expect(shown <= peak + 1e-9 && shown >= peak * 31 / 32 - 1e-9, "the stretches laid over one another reach the light's peak")
        }
        let glint = BeamLayerView.bands(BeamLight.glint)
        let middle = try #require(glint.last)
        #expect(abs((middle.from + middle.to) / 2 - BeamLight.glintCenter) < 0.01, "the brightest stretch is centred on the glint")
    }

    @Test func aPathsLengthFollowsItsCurves() {
        let square = Path(CGRect(x: 0, y: 0, width: 100, height: 50)).cgPath
        #expect(abs(BeamLayerView.length(of: square) - 300) < 1e-9)
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100)).cgPath
        #expect(abs(BeamLayerView.length(of: circle) - 100 * .pi) < 0.1)
    }
}
