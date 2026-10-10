//
//  PanelSections.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// What a panel needs to draw itself in pieces. In the environment only while the setting is on.
struct PanelPieces: Equatable {
    var look: LauncherLook
    var fieldShape: SearchFieldShape
    var heights: PanelPieceHeights

    func fieldOutline() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: fieldShape.fieldPieceRadius(height: heights.field), style: fieldShape.pieceCornerStyle)
    }

    /// The look for the field's piece. Collapsed there is nothing under it, so its shadow is whole.
    func fieldAppearance(facesResults: Bool) -> LauncherPanelAppearance {
        var appearance = LauncherPanelAppearance(look)
        appearance.cornerRadius = fieldShape.fieldPieceRadius(height: heights.field)
        appearance.cornerStyle = fieldShape.pieceCornerStyle
        appearance.shadow = .piece(facing: facesResults ? .bottom : nil)
        appearance.span = heights.fieldSpan
        return appearance
    }

    /// How far a list sits from the edges of the piece it is in (see the lists' content margins).
    static let listInset = ThawSpacing.base

    /// The corner of a row's highlight in the results piece: the piece's radius less the list's inset, so the
    /// first row's corners share a centre with the piece's. Never less than a control's, which a square piece keeps.
    var rowRadius: CGFloat {
        max(ThawRadius.control, fieldShape.panelPieceRadius - Self.listInset)
    }

    func resultsAppearance() -> LauncherPanelAppearance {
        var appearance = LauncherPanelAppearance(look)
        appearance.cornerRadius = fieldShape.panelPieceRadius
        appearance.shadow = .piece(facing: .top)
        appearance.span = heights.resultsSpan
        return appearance
    }

    /// A view with no search field stays one piece, with the corners the results have.
    func wholeAppearance() -> LauncherPanelAppearance {
        var appearance = LauncherPanelAppearance(look)
        appearance.cornerRadius = fieldShape.panelPieceRadius
        return appearance
    }
}

extension EnvironmentValues {
    /// Set by the launcher and the picker while the search field is separate; nil draws one panel.
    @Entry var panelPieces: PanelPieces?
    /// Set for the field that is its own piece: it draws no glass and marks focus on this outline.
    @Entry var fieldPieceOutline: RoundedRectangle?
}

/// A search field over its content, as every view with a field at the top is laid out:
/// one stack inside the panel, or two pieces of glass with a gap between them.
struct PanelSections<Header: View, Content: View>: View {
    var showsContent = true
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @Environment(\.panelPieces) private var pieces

    var body: some View {
        if let pieces {
            VStack(spacing: pieces.heights.gap) {
                // Each piece's content keeps a container of its own, as the panel's content has under its glass.
                GlassEffectContainer { header }
                    .frame(maxWidth: .infinity)
                    .frame(height: pieces.heights.field)
                    .environment(\.fieldPieceOutline, pieces.fieldOutline())
                    .modifier(pieces.fieldAppearance(facesResults: showsContent))
                if showsContent {
                    GlassEffectContainer {
                        VStack(spacing: 0) { content }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: pieces.heights.results)
                    .environment(\.searchRowCornerRadius, pieces.rowRadius)
                    .modifier(pieces.resultsAppearance())
                }
            }
        } else {
            VStack(spacing: 0) {
                header
                if showsContent {
                    content
                }
            }
        }
    }
}

/// For a view with no search field: while the pieces are separate the look is drawn here, around the whole view.
struct PanelOnePiece: ViewModifier {
    @Environment(\.panelPieces) private var pieces

    func body(content: Content) -> some View {
        if let pieces {
            GlassEffectContainer { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(pieces.wholeAppearance())
        } else {
            content
        }
    }
}

/// The look around the whole panel, or handed down for the views to draw piece by piece.
struct PanelLook: ViewModifier {
    let look: LauncherLook
    let pieces: PanelPieces?

    func body(content: Content) -> some View {
        if let pieces {
            content.environment(\.panelPieces, pieces)
        } else {
            content.modifier(LauncherPanelAppearance(look))
        }
    }
}
