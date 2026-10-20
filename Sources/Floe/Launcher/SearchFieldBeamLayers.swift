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
            if index > 0 {
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
            gradient.add(Self.spin(at: key.frameRate), forKey: "turn")
        }
        return gradient
    }

    /// One turn every `turn` seconds, at the same place in the turn for every layer, the field's and the glow's.
    private static func spin(at frameRate: Float) -> CAAnimation {
        let turn = SearchFieldBeamView<Rectangle>.turn
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = turn
        spin.repeatCount = .infinity
        spin.timeOffset = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: turn)
        spin.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        return spin
    }

    /// The second hue fades in and out over the first, as the colours drift one way and back.
    private static func drift(at frameRate: Float) -> CAAnimation {
        let period = SearchFieldBeamView<Rectangle>.drift.period
        let drift = CABasicAnimation(keyPath: "opacity")
        drift.fromValue = 0
        drift.toValue = 1
        drift.duration = period / 2
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        drift.timeOffset = (Date.timeIntervalSinceReferenceDate + period / 4).truncatingRemainder(dividingBy: period)
        drift.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        return drift
    }
}
