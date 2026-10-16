//
//  PointerRest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// Where the pointer rested when the panel opened or a key was last pressed. A row that the keys or
/// a new list slide under a pointer that has not moved since is not marked as hovered.
final class PointerRest {
    /// How far the pointer has to move, in points, before rows under it are marked again.
    static let slack: CGFloat = 2

    private var anchor: CGPoint?
    private var moved = true

    func rest(at location: CGPoint = NSEvent.mouseLocation) {
        anchor = location
        moved = false
    }

    /// Whether the pointer has left its resting place, which it then stays off until the next rest.
    func hasMoved(to location: CGPoint = NSEvent.mouseLocation) -> Bool {
        if !moved, let anchor, hypot(location.x - anchor.x, location.y - anchor.y) > Self.slack {
            moved = true
        }
        return moved
    }
}

extension EnvironmentValues {
    /// The launcher's resting pointer. Without one a row is marked whenever the pointer is over it.
    @Entry var pointerRest: PointerRest?
}

/// Whether the pointer is over the view and has moved since it last rested.
struct PointerHover: ViewModifier {
    @Binding var isHovering: Bool
    @Environment(\.pointerRest) private var rest

    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            let hovering = switch phase {
            case .active: rest?.hasMoved() ?? true
            case .ended: false
            }
            if hovering != isHovering {
                isHovering = hovering
            }
        }
    }
}
