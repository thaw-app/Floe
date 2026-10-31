//
//  SearchFieldShape.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// The outline of the launcher's search field.
public nonisolated enum SearchFieldShape: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The corners the rest of the panel's controls have.
    case rounded
    /// Ends rounded off into half circles.
    case capsule
    case square

    public var id: String {
        rawValue
    }

    /// The corner radius for a field of a given height.
    public func cornerRadius(height: CGFloat) -> CGFloat {
        switch self {
        case .rounded: ThawRadius.control
        case .capsule: height / 2
        case .square: 0
        }
    }

    /// Standing alone the field is a piece of the panel, so rounded takes the panel's corner and not a control's.
    public func fieldPieceRadius(height: CGFloat) -> CGFloat {
        switch self {
        case .rounded: ThawRadius.panel
        case .capsule: height / 2
        case .square: 0
        }
    }

    /// The piece under a separate field, and a panel in one piece beside it: only square squares it.
    public var panelPieceRadius: CGFloat {
        self == .square ? 0 : ThawRadius.panel
    }

    /// A continuous corner as large as half the height leaves a nick, so a capsule's is circular.
    public var pieceCornerStyle: RoundedCornerStyle {
        self == .capsule ? .circular : .continuous
    }

    /// The outline itself. A capsule is its own shape, since the field's height is not known where this is asked.
    public var outline: SearchFieldOutline {
        SearchFieldOutline(shape: self)
    }
}

/// One shape type for all three outlines, so the glass that draws the field takes any of them.
public nonisolated struct SearchFieldOutline: InsettableShape {
    public let shape: SearchFieldShape
    public var inset: CGFloat = 0

    public func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = max(min(shape.cornerRadius(height: rect.height), rect.height / 2, rect.width / 2), 0)
        // A continuous corner as large as half the height leaves a nick where it meets the straight edge.
        return Path(roundedRect: rect, cornerRadius: radius, style: shape == .capsule ? .circular : .continuous)
    }

    public func inset(by amount: CGFloat) -> SearchFieldOutline {
        SearchFieldOutline(shape: shape, inset: inset + amount)
    }
}

extension EnvironmentValues {
    /// Read by the search field, set by the launcher from the setting: the field itself knows nothing of settings.
    @Entry public var searchFieldShape: SearchFieldShape = .rounded
    /// The same for the beam around the field.
    @Entry public var searchFieldBeam: SearchFieldBeam = .off
    @Entry public var searchFieldBeamFrameRate = 60.0
}
