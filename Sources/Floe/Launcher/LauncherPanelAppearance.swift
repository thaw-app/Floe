//
//  LauncherPanelAppearance.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The launcher's glass, tint, border and shadow, layered in that order under the content.
/// The shadow follows the rounded shape: the window's own is a square, `margin` larger than the launcher.
struct LauncherPanelAppearance: ViewModifier {
    /// How the shadow is drawn: around a panel in one piece, or for one of two pieces.
    enum Shadow: Equatable {
        case panel
        /// Nothing is cast toward `facing`, where the other piece is, so the gap between them stays clear.
        case piece(facing: VerticalEdge?)
    }

    let glass: LauncherGlass
    let tint: LauncherTint
    let border: LauncherBorder?
    let hasShadow: Bool
    var cornerRadius = ThawRadius.panel
    var cornerStyle = RoundedCornerStyle.continuous
    var shadow = Shadow.panel
    /// The share of the launcher's height this piece covers, for the fade Dynamic Glass runs down it.
    var span: ClosedRange<CGFloat> = 0 ... 1

    init(glass: LauncherGlass, tint: LauncherTint, border: LauncherBorder?, hasShadow: Bool) {
        self.glass = glass
        self.tint = tint
        self.border = border
        self.hasShadow = hasShadow
    }

    init(_ look: LauncherLook) {
        self.init(glass: look.glass, tint: look.tint, border: look.border, hasShadow: look.hasShadow)
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle)
    }

    func body(content: Content) -> some View {
        let style = glass.resolvedStyle()
        let length = span.upperBound - span.lowerBound
        // The tint is the content's background, so the order is glass, tint,
        // content: a colour wash must never sit on top of the launcher's text.
        // With transparency turned down there is no glass to wash, so the wash is drawn as a fill.
        let wash = reduceTransparency ? glass.tintColor(for: style).map { AnyShapeStyle(Color(nsColor: $0)) } : nil
        let tinted = content.background {
            if let style = tint.backgroundStyle ?? wash {
                if span == 0 ... 1 {
                    shape.fill(style)
                } else {
                    // One of two pieces shows its part of the fill, so a gradient runs down both and does not start over.
                    Rectangle().fill(style)
                        .scaleEffect(y: 1 / length, anchor: UnitPoint(x: 0.5, y: span.lowerBound / (1 - length)))
                        .clipShape(shape)
                }
            }
        }
        let glazed = Group {
            // Regular is the panel's own glass, which also knows what to draw
            // when the system has transparency turned down.
            if style == .regular || reduceTransparency {
                tinted.thawGlass(.borderlessPanel, in: shape)
            } else {
                tinted
                    // The fade is black at the top whatever the appearance, so
                    // the content over it is always the dark one's.
                    .environment(\.colorScheme, style.usesDarkFade ? .dark : colorScheme)
                    .background {
                        LauncherGlassBackdrop(style: style, tint: glass.tintColor(for: style), cornerRadius: cornerRadius, cornerStyle: cornerStyle, span: span)
                    }
            }
        }
        let bordered = Group {
            if let border {
                glazed.overlay(shape.strokeBorder(border.color.color, lineWidth: border.width))
            } else {
                glazed
            }
        }
        return Group {
            if hasShadow {
                switch shadow {
                case .panel:
                    bordered.shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                case let .piece(facing):
                    // Its own layer, so the facing edge changes without rebuilding the piece and its field.
                    bordered.background { PieceShadow(shape: shape, facing: facing) }
                }
            } else {
                bordered
            }
        }
    }
}

/// The panel's shadow for one of two pieces, fading out toward the edge that faces the other piece:
/// a full shadow from each would meet in the gap as a dark band.
private struct PieceShadow: View {
    let shape: RoundedRectangle
    let facing: VerticalEdge?

    /// The shadow's own radius, so it is gone by the time it reaches the edge.
    private static let fade: CGFloat = 14

    var body: some View {
        shape.fill(.black.opacity(0.35))
            .blur(radius: 14)
            .offset(y: 6)
            .mask {
                ZStack {
                    VStack(spacing: 0) {
                        if facing == .top {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                        }
                        Rectangle()
                        if facing == .bottom {
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                        }
                    }
                    // Past the piece on every side but the facing one, as far as the window's margin reaches.
                    .padding(.horizontal, -LauncherView.margin)
                    .padding(.top, facing == .top ? 0 : -LauncherView.margin)
                    .padding(.bottom, facing == .bottom ? 0 : -LauncherView.margin)
                    // Under the piece itself the shadow is whole, as it is under a panel in one piece.
                    shape
                }
            }
            .allowsHitTesting(false)
    }
}
