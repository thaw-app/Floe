//
//  SearchFieldBeam.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

/// The light inside the search field's border, in one of a few sets of colours. The technique is border-beam's, by
/// Jakub Antalik: soft colour fixed on each side, shown through a wide turning window, all of it inside the field.
nonisolated enum SearchFieldBeam: String, Codable, CaseIterable, Identifiable {
    case off
    case colorful
    case mono
    case ocean
    case sunset

    /// A soft patch of colour on the field's edge.
    struct Blob: Equatable {
        var color: Color
        /// Where its middle is, as a part of the field's width and height: an edge is 0 or 1.
        var center: UnitPoint
        /// How far it reaches across and down, in points.
        var radii: CGSize
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .off: String(localized: "Off", bundle: .floe, comment: "No beam around the search field.")
        case .colorful: String(localized: "Colorful", bundle: .floe, comment: "A beam around the search field in every colour.")
        case .mono: String(localized: "Mono", bundle: .floe, comment: "A beam around the search field in greys alone.")
        case .ocean: String(localized: "Ocean", bundle: .floe, comment: "A beam around the search field in blues and violets.")
        case .sunset: String(localized: "Sunset", bundle: .floe, comment: "A beam around the search field in oranges, pinks and reds.")
        }
    }

    /// The same places for every set: along the top, down the left, along the bottom and down the right.
    private static let places: [(center: UnitPoint, radii: CGSize)] = [
        (UnitPoint(x: 0.3, y: 0), CGSize(width: 80, height: 30)),
        (UnitPoint(x: 0.08, y: 0.05), CGSize(width: 50, height: 28)),
        (UnitPoint(x: 0, y: 0.7), CGSize(width: 34, height: 56)),
        (UnitPoint(x: 0, y: 0.7), CGSize(width: 18, height: 30)),
        (UnitPoint(x: 0.72, y: 1), CGSize(width: 160, height: 28)),
        (UnitPoint(x: 0.5, y: 1), CGSize(width: 80, height: 24)),
        (UnitPoint(x: 0.93, y: 0), CGSize(width: 70, height: 30)),
        (UnitPoint(x: 1, y: 0.3), CGSize(width: 26, height: 40)),
        (UnitPoint(x: 1, y: 0.3), CGSize(width: 50, height: 44)),
    ]

    /// One colour for each place, in the same order.
    private var palette: [Color] {
        switch self {
        case .off: []
        case .colorful: [rgb(255, 60, 110), rgb(50, 140, 255), rgb(60, 200, 90), rgb(30, 190, 175), rgb(110, 75, 255), rgb(50, 140, 255), rgb(255, 125, 45), rgb(240, 55, 180), rgb(180, 45, 240)]
        case .mono: [175, 140, 160, 130, 170, 150, 190, 145, 165].map { rgb($0, $0, $0) }
        case .ocean: [rgb(100, 85, 225), rgb(60, 120, 255), rgb(80, 105, 205), rgb(50, 145, 225), rgb(120, 85, 255), rgb(70, 130, 255), rgb(140, 105, 240), rgb(90, 115, 230), rgb(130, 75, 255)]
        case .sunset: [rgb(255, 85, 55), rgb(255, 160, 45), rgb(255, 125, 65), rgb(255, 200, 55), rgb(255, 105, 85), rgb(255, 145, 50), rgb(250, 70, 120), rgb(255, 180, 60), rgb(235, 60, 95)]
        }
    }

    /// The set's colours round the field, the first again at the end so they meet without a seam.
    var ring: [Color] {
        palette.first.map { palette + [$0] } ?? []
    }

    var blobs: [Blob] {
        zip(Self.places, palette).map { Blob(color: $1, center: $0.center, radii: $0.radii) }
    }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
}

/// Draws the beam inside an outline: each side's colour seen through a window that turns every two seconds, as a
/// hairline, a glow into the field and a glint. The still parts are drawn once for the field's size, and Core
/// Animation turns the windows, so the launcher does no work while the beam goes round. With Reduce Motion the
/// window stands still.
struct SearchFieldBeamView<Outline: InsettableShape>: View {
    /// The beam is drawn in two layers, one over the field and one under its text.
    enum Part {
        /// The hairline on the border and its glint. Over the field.
        case edge
        /// The glow into the field. Under the text, so what is typed is never tinted.
        case spill
    }

    let outline: Outline
    let beam: SearchFieldBeam
    var part = Part.edge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.searchFieldBeamFrameRate) private var frameRate
    @State private var isShown = false

    /// Seconds for the window to go once round.
    static var turn: Double {
        2
    }

    /// How bright the whole beam is: every layer's strength is a share of it.
    private static var intensity: Double {
        1
    }

    /// How far the light reaches in from the border, as a share of its full size: every width, blur and patch
    /// is scaled by it, so the field keeps its room.
    private static var reach: CGFloat {
        0.5
    }

    /// Seconds for the colours to drift one way and back, and how far, in degrees of hue.
    static var drift: (period: Double, range: Double) {
        (12, 30)
    }

    var body: some View {
        GeometryReader { proxy in
            let key = BeamLayerView.Key(
                size: proxy.size,
                scale: displayScale,
                outline: outline.path(in: CGRect(origin: .zero, size: proxy.size)),
                beam: beam,
                isEdge: part == .edge,
                isDark: isDark,
                isStill: reduceMotion,
                frameRate: Float(frameRate)
            )
            BeamLayers(key: key) { layers(size: proxy.size) }
        }
        .opacity(isShown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { isShown = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    /// The part's layers for a field of that size, with their still parts drawn.
    private func layers(size: CGSize) -> [BeamLayer] {
        // Mono's greys are weaker, or they read as a grey smudge.
        let strength = Float((beam == .mono ? 0.6 : 1) * Self.intensity)
        let light = (isDark ? NSColor.white : NSColor.black).cgColor
        // Two hues to drift between, or the one the colours have when they stand still.
        let hues: [Angle] = reduceMotion ? [.zero] : [.degrees(-Self.drift.range), .degrees(Self.drift.range)]
        func drawn(_ content: some View) -> CGImage? {
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
            renderer.scale = displayScale
            return renderer.cgImage
        }
        switch part {
        case .edge:
            // The rim: the colours just inside the border, soft, so the field looks lit from its edge.
            let rim = BeamLayer(
                colour: hues.compactMap { drawn(colour(hue: $0).mask(outline.stroke(lineWidth: 8 * Self.reach)).blur(radius: 6 * Self.reach)) },
                window: BeamLight.glowWindow,
                opacity: (isDark ? 0.75 : 0.6) * strength
            )
            let hairline = BeamLayer(
                colour: hues.compactMap { drawn(colour(hue: $0).mask(self.hairline)) },
                glint: drawn(self.hairline).map { BeamLayer.Glint(stops: BeamLight.glint, light: light, mask: $0) },
                window: BeamLight.hairlineWindow,
                opacity: (isDark ? 1 : 0.8) * strength
            )
            // The glint again, softened, which is what makes the hairline seem to give off light.
            let bloom = BeamLayer(
                glint: drawn(outline.stroke(lineWidth: 2).blur(radius: 6 * Self.reach)).map { BeamLayer.Glint(stops: BeamLight.bloom, light: light, mask: $0) },
                opacity: (isDark ? 0.6 : 0.45) * strength
            )
            return [rim, hairline, bloom]
        case .spill:
            let band = hues.compactMap { hue in
                drawn(
                    ZStack {
                        colour(hue: hue)
                            .opacity(0.7)
                        outline
                            .stroke(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.14), lineWidth: 2)
                            .blur(radius: 5 * Self.reach)
                    }
                    // A band along the border, not the whole field: the middle is the text's.
                    .mask(outline.stroke(lineWidth: 32 * Self.reach).blur(radius: 12 * Self.reach))
                )
            }
            return [BeamLayer(colour: band, window: BeamLight.glowWindow, opacity: (isDark ? 0.7 : 0.5) * strength)]
        }
    }

    private var hairline: some View {
        outline.inset(by: 0.75).stroke(lineWidth: 1.5)
    }

    /// The colours of each side: the set's colours all the way round, so no stretch of the border is left dark,
    /// and brighter patches where the beam puts them.
    private func colour(hue: Angle) -> some View {
        ZStack {
            AngularGradient(colors: beam.ring, center: .center)
                .opacity(0.6)
            patches
        }
        .hueRotation(hue)
        .saturation(isDark ? 1.3 : 1.6)
    }

    private var patches: some View {
        Canvas { context, size in
            for blob in beam.blobs {
                let center = CGPoint(x: blob.center.x * size.width, y: blob.center.y * size.height)
                var patch = context
                // Squashed from a circle, so the patch is as wide and as tall as the beam asks.
                patch.translateBy(x: center.x, y: center.y)
                patch.scaleBy(x: 1, y: blob.radii.height / blob.radii.width)
                let reach = blob.radii.width * Self.reach
                patch.fill(
                    Path(ellipseIn: CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)),
                    with: .radialGradient(Gradient(colors: [blob.color, blob.color.opacity(0)]), center: .zero, startRadius: 0, endRadius: reach)
                )
            }
        }
    }
}

/// How the beam's light falls round the field, as stops from nothing to full and back: each a part of the turn
/// and how strong the light is there.
private enum BeamLight {
    /// Where round the field the hairline shows, from nothing to full and back, as parts of the turn.
    static let hairlineWindow: [(Double, Double)] = [
        (0, 0), (0.3, 0), (0.36, 0.1), (0.44, 0.35), (0.52, 1), (0.8, 1), (0.86, 0.35), (0.92, 0.1), (0.95, 0), (1, 0),
    ]

    /// The same for the glow, a little wider.
    static let glowWindow: [(Double, Double)] = [
        (0, 0), (0.22, 0), (0.28, 0.12), (0.36, 0.4), (0.46, 1), (0.82, 1), (0.88, 0.4), (0.94, 0.12), (0.97, 0), (1, 0),
    ]

    /// The bright place on the hairline, near the window's leading end.
    static let glint: [(Double, Double)] = [
        (0, 0), (0.54, 0), (0.57, 0.1), (0.6, 0.3), (0.63, 0.6), (0.66, 0.75), (0.69, 0.6), (0.72, 0.3), (0.75, 0.1), (0.78, 0), (1, 0),
    ]

    /// The glint's softer twin, which the blur spreads.
    static let bloom: [(Double, Double)] = [
        (0, 0), (0.58, 0), (0.65, 0.08), (0.69, 0.45), (0.7, 0.85), (0.705, 0.85), (0.715, 0.45), (0.75, 0.08), (0.82, 0), (1, 0),
    ]
}
