//
//  LauncherAppearancePreview.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// A miniature launcher that runs the exact panel appearance pipeline, so the
/// glass, tint, border and shadow read live next to their controls.
struct LauncherAppearancePreview: View {
    let glass: LauncherGlass
    let tint: LauncherTint
    let border: LauncherBorder?
    let hasShadow: Bool
    var corners = SearchFieldCorners.rounded
    /// The field as its own piece, or the one panel.
    var separatesField = false

    /// The miniature's pieces, at half the launcher's field and gap, over the two rows.
    private static let heights = PanelPieceHeights(field: 34, gap: ThawSpacing.tight, results: 60)

    var body: some View {
        if separatesField {
            VStack(spacing: Self.heights.gap) {
                field
                    .padding(.horizontal, 12)
                    .frame(height: Self.heights.field)
                    // At this scale a control's corner stands for the panel's.
                    .modifier(piece(radius: corners.cornerRadius(height: Self.heights.field), style: corners.pieceCornerStyle, facing: .bottom, span: Self.heights.fieldSpan))
                rows
                    .padding(12)
                    .frame(height: Self.heights.results)
                    .modifier(piece(radius: corners.panelPieceRadius, style: .continuous, facing: .top, span: Self.heights.resultsSpan))
            }
            .padding(6)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                field
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quinary, in: corners.outline)
                rows
            }
            .padding(12)
            .modifier(LauncherPanelAppearance(glass: glass, tint: tint, border: border, hasShadow: hasShadow))
            .padding(6)
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Search")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewRow(width: 150)
            previewRow(width: 110)
        }
    }

    private func piece(radius: CGFloat, style: RoundedCornerStyle, facing: VerticalEdge, span: ClosedRange<CGFloat>) -> LauncherPanelAppearance {
        var appearance = LauncherPanelAppearance(glass: glass, tint: tint, border: border, hasShadow: hasShadow)
        appearance.cornerRadius = radius
        appearance.cornerStyle = style
        appearance.shadow = .piece(facing: facing)
        appearance.span = span
        return appearance
    }

    private func previewRow(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle().fill(.quinary).frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.quinary)
                .frame(width: width, height: 8)
            Spacer()
        }
    }
}

/// A desktop for the preview to sit on, light or dark with the window, so the glass and tint read against colour.
struct PreviewBackdrop: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> LinearGradient {
        let colors: [Color] = environment.colorScheme == .dark
            ? [Color(red: 0.13, green: 0.17, blue: 0.29), Color(red: 0.30, green: 0.18, blue: 0.27)]
            : [Color(red: 0.55, green: 0.71, blue: 0.86), Color(red: 0.93, green: 0.76, blue: 0.62)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
