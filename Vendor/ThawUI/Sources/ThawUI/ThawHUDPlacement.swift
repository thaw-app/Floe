//
//  ThawHUDPlacement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Where along the top of a display a ThawHUD capsule sits.
///
/// Confirmations do not need this: they answer a gesture the user just made
/// and are already being looked for, so the center is the right place and the
/// only place. Announcements do. The recording watch's banners arrive
/// unrequested and land on a display the user may not be facing, and the
/// center of a wide display is also where the thing being worked on usually
/// is, the one spot a banner is most likely to be in the way of.
public nonisolated enum ThawHUDPlacement: String, CaseIterable, Hashable, Sendable {
    /// Under the left end of the menu bar, past the application menus.
    case leading
    /// Under the middle of the menu bar. What every HUD caller gets unless it
    /// asks otherwise.
    case center
    /// Under the right end of the menu bar, nearest the status items the
    /// camera and microphone indicators appear in themselves.
    case trailing

    /// How far the off-center cases stay clear of the screen's edge, where a
    /// rounded display corner would otherwise clip the capsule.
    public static let edgeInset: CGFloat = 16

    /// The smallest capsule, so a one-word label does not shrink to a dot.
    public static let minimumSize = CGSize(width: 120, height: 34)

    /// The space between the menu bar and the capsule.
    public static let gap: CGFloat = 8

    /// The capsule's left edge for a capsule width wide on screenFrame.
    ///
    /// Pure math over the frame, so all three cases are decidable without a
    /// display attached.
    public func originX(screenFrame: CGRect, width: CGFloat) -> CGFloat {
        switch self {
        case .leading:
            screenFrame.minX + Self.edgeInset
        case .center:
            screenFrame.midX - width / 2
        case .trailing:
            screenFrame.maxX - width - Self.edgeInset
        }
    }

    /// The capsule's size for content that wants fitting: at least the minimum, and never wider
    /// than the screen less both edge insets, so long text truncates instead of running off a display.
    public static func size(fitting: CGSize, screenFrame: CGRect) -> CGSize {
        let widest = max(minimumSize.width, screenFrame.width - edgeInset * 2)
        return CGSize(
            width: min(max(fitting.width, minimumSize.width), widest),
            height: max(fitting.height, minimumSize.height)
        )
    }

    /// The menu bar's height on a screen: the strip between the top of its frame and the top of its
    /// visible frame. A full-screen space hides the bar and leaves no strip, so fallback stands in.
    public static func menuBarHeight(screenFrame: CGRect, visibleFrame: CGRect, fallback: CGFloat) -> CGFloat {
        let strip = screenFrame.maxY - visibleFrame.maxY
        return strip > 0 ? strip : fallback
    }

    /// Places the capsule just below the menu bar, in AppKit's bottom-left-origin coordinates.
    public func frame(fitting: CGSize, screenFrame: CGRect, menuBarHeight: CGFloat) -> CGRect {
        let size = Self.size(fitting: fitting, screenFrame: screenFrame)
        return CGRect(
            x: originX(screenFrame: screenFrame, width: size.width),
            y: screenFrame.maxY - menuBarHeight - Self.gap - size.height,
            width: size.width,
            height: size.height
        )
    }
}
