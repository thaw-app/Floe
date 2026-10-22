//
//  SearchFieldBeamLayers.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

/// One layer of the beam: still colour, a turning light over it, or both, seen through a turning window.
struct BeamLayer {
    /// A light that turns with the window, seen through a still mask.
    struct Glint {
        let stops: [(Double, Double)]
        let light: CGColor
        let mask: CGImage
    }

    /// The colour at each of the two hues it drifts between, or at the one it stands still at.
    var colour: [CGImage] = []
    var glint: Glint?
    /// Where round the field the layer shows. Nil for all the way round.
    var window: [(Double, Double)]?
    var opacity: Float
}

struct BeamLayers: NSViewRepresentable {
    let key: BeamLayerView.Key
    let layers: () -> [BeamLayer]

    func makeNSView(context _: Context) -> BeamLayerView {
        BeamLayerView()
    }

    func updateNSView(_ view: BeamLayerView, context _: Context) {
        view.show(key, layers)
    }
}

/// The beam as Core Animation layers. They are made again only when the field's size or look changes.
final class BeamLayerView: NSView {
    struct Key: Equatable {
        let size: CGSize
        let scale: CGFloat
        let outline: Path
        let beam: SearchFieldBeam
        let isEdge: Bool
        let isDark: Bool
        let isStill: Bool
        let frameRate: Float
    }

    // One monotonic clock for the edge, spill and rebuilt layers, independent of image-rendering time.
    private static let animationEpoch = CACurrentMediaTime()
    private var key: Key?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    func show(_ key: Key, _ layers: () -> [BeamLayer]) {
        guard key != self.key, key.size.width > 0, key.size.height > 0, let root = layer else { return }
        self.key = key
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let bounds = CGRect(origin: .zero, size: key.size)
        let clip = CALayer()
        clip.frame = bounds
        let shape = CAShapeLayer()
        shape.path = key.outline.cgPath
        clip.mask = shape
        for beamLayer in layers() {
            clip.addSublayer(make(beamLayer, in: bounds, key: key))
        }
        root.sublayers = [clip]
    }

    private func make(_ beamLayer: BeamLayer, in bounds: CGRect, key: Key) -> CALayer {
        let group = CALayer()
        group.frame = bounds
        group.opacity = beamLayer.opacity
        for (index, image) in beamLayer.colour.enumerated() {
            let colour = picture(image, in: bounds, scale: key.scale)
            if index > 0, !key.isStill {
                colour.add(Self.drift(at: key.frameRate), forKey: "drift")
            }
            group.addSublayer(colour)
        }
        if let glint = beamLayer.glint {
            let holder = CALayer()
            holder.frame = bounds
            holder.mask = picture(glint.mask, in: bounds, scale: key.scale)
            holder.addSublayer(turning(glint.stops, light: glint.light, in: bounds, key: key))
            group.addSublayer(holder)
        }
        if let window = beamLayer.window {
            group.mask = turning(window, light: NSColor.white.cgColor, in: bounds, key: key)
        }
        return group
    }

    private func picture(_ image: CGImage, in bounds: CGRect, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        layer.contents = image
        layer.contentsScale = scale
        return layer
    }

    /// A light going round from the field's middle, as wide as the field's diagonal so turning it never shows a corner.
    private func turning(_ stops: [(Double, Double)], light: CGColor, in bounds: CGRect, key: Key) -> CALayer {
        let side = hypot(bounds.width, bounds.height).rounded(.up)
        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.colors = stops.map { light.copy(alpha: light.alpha * $0.1) ?? light }
        gradient.locations = stops.map { NSNumber(value: $0.0) }
        if key.isStill {
            gradient.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        } else {
            gradient.add(Self.spin(at: key.frameRate, in: key.size), forKey: "turn")
        }
        return gradient
    }

    /// One turn every `turn` seconds, at the same place in the turn for every layer, the field's and the glow's.
    /// The light keeps one speed along the border, so on a wide field it does not rush round the short ends.
    static func spin(at frameRate: Float, in size: CGSize) -> CAAnimation {
        let turn = SearchFieldBeamView<Rectangle>.turn
        return interpolated("transform.rotation.z", over: turn, at: frameRate) {
            // The bright spot, not the transparent start of the gradient, follows the border.
            angle(along: $0, of: size) - BeamLight.glintCenter * 2 * .pi
        }
    }

    /// The second hue fades in and out over the first, as the colours drift one way and back.
    static func drift(at frameRate: Float) -> CAAnimation {
        let period = SearchFieldBeamView<Rectangle>.drift.period
        let drift = interpolated("opacity", over: period, at: frameRate) { (1 - cos(2 * .pi * $0)) / 2 }
        drift.timeOffset = period / 4
        return drift
    }

    /// The angle from the middle of a field of that size to the point a share of the way round its border,
    /// starting at the middle of the right side. It only grows, from 0 to a full turn.
    static func angle(along share: Double, of size: CGSize) -> Double {
        let half = (width: max(size.width, 1) / 2, height: max(size.height, 1) / 2)
        // Round from the right side's middle: the rest of that side, a long side, a short side, a long side, back.
        var left = share * 4 * (half.width + half.height)
        let sides: [(length: CGFloat, point: (CGFloat) -> CGPoint)] = [
            (half.height, { CGPoint(x: half.width, y: $0) }),
            (2 * half.width, { CGPoint(x: half.width - $0, y: half.height) }),
            (2 * half.height, { CGPoint(x: -half.width, y: half.height - $0) }),
            (2 * half.width, { CGPoint(x: -half.width + $0, y: -half.height) }),
            (half.height, { CGPoint(x: half.width, y: -half.height + $0) }),
        ]
        for side in sides {
            guard left < side.length else {
                left -= side.length
                continue
            }
            let point = side.point(left)
            let angle = atan2(point.y, point.x)
            return angle < 0 ? angle + 2 * .pi : angle
        }
        return 2 * .pi
    }

    /// Samples describe the curve, not a frame cap. Interpolation lets the compositor follow its actual cadence.
    private static func interpolated(_ keyPath: String, over duration: Double, at frameRate: Float, value: (Double) -> Double) -> CAKeyframeAnimation {
        let steps = max(1, Int((duration * 120).rounded()))
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0 ... steps).map { value(Double($0) / Double(steps)) }
        animation.keyTimes = (0 ... steps).map { NSNumber(value: Double($0) / Double(steps)) }
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = duration
        animation.beginTime = animationEpoch
        animation.repeatCount = .infinity
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        return animation
    }
}
