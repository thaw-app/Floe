//
//  WindowTiling.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
import Foundation

/// A part of the screen a window can be tiled to.
nonisolated enum WindowTile: Sendable {
    case left
    case right
    case top
    case bottom
    case maximized
    case centered

    /// The part of the area this tile covers. Halves are whole points, and the right and bottom ones
    /// take what is left, so two tiles side by side meet with no gap on a screen of odd size.
    /// A centered window keeps its size, shrunk to fit the area when it is larger.
    func frame(in area: CGRect, for window: CGSize) -> CGRect {
        let halfWidth = (area.width / 2).rounded(.down)
        let halfHeight = (area.height / 2).rounded(.down)
        switch self {
        case .left:
            return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        case .right:
            return CGRect(x: area.minX + halfWidth, y: area.minY, width: area.width - halfWidth, height: area.height)
        case .top:
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
        case .bottom:
            return CGRect(x: area.minX, y: area.minY + halfHeight, width: area.width, height: area.height - halfHeight)
        case .maximized:
            return area
        case .centered:
            let size = CGSize(width: min(window.width, area.width), height: min(window.height, area.height))
            let origin = CGPoint(
                x: area.minX + ((area.width - size.width) / 2).rounded(.down),
                y: area.minY + ((area.height - size.height) / 2).rounded(.down)
            )
            return CGRect(origin: origin, size: size)
        }
    }
}

extension SystemCommand {
    /// The tile a system command moves the window to. Nil for every other one.
    nonisolated var tile: WindowTile? {
        switch self {
        case .tileWindowLeft: .left
        case .tileWindowRight: .right
        case .tileWindowTop: .top
        case .tileWindowBottom: .bottom
        case .maximizeWindow: .maximized
        case .centerWindow: .centered
        default: nil
        }
    }
}

/// The window being tiled, as far as tiling needs it. Frames use Accessibility's coordinates: the origin
/// is the top left of the main display and y grows downward.
nonisolated protocol TilableWindow {
    var frame: CGRect? { get }
    var isFullScreen: Bool { get }
    func move(to origin: CGPoint) -> Bool
    func resize(to size: CGSize) -> Bool
}

nonisolated enum WindowTiling {
    enum Outcome: Equatable {
        case tiled
        case noWindow
        case fullScreen
        case refused

        /// The line for the HUD. A window that moved says enough by moving.
        var message: String? {
            switch self {
            case .tiled: nil
            case .noWindow: String(localized: "No window to tile", bundle: .floe, comment: "Shown when the user asks to tile a window and the app in front has none.")
            case .fullScreen: String(localized: "A full-screen window can't be tiled", bundle: .floe)
            case .refused: String(localized: "This window can't be moved", bundle: .floe)
            }
        }
    }

    static func tile(_ window: some TilableWindow, to tile: WindowTile, screens: [CGRect]) -> Outcome {
        guard !window.isFullScreen else { return .fullScreen }
        guard let current = window.frame, let area = area(for: current, among: screens) else { return .noWindow }
        return place(window, at: tile.frame(in: area, for: current.size), from: current, in: area)
    }

    /// Moves and sizes the window from current to target, then keeps it on area.
    static func place(_ window: some TilableWindow, at target: CGRect, from current: CGRect, in area: CGRect) -> Outcome {
        // macOS limits a window's size to the screen it is on, so a window going to a bigger screen
        // is sized again once it is there, and one going to a smaller screen is sized before it leaves.
        // A window that keeps its size isn't asked to resize, as one with a fixed size refuses that.
        let resizes = target.size != current.size
        guard !resizes || window.resize(to: target.size) else { return .refused }
        guard window.move(to: target.origin), !resizes || window.resize(to: target.size) else {
            // A window that was resized but won't move goes back to its old size and place.
            _ = window.move(to: current.origin)
            if resizes {
                _ = window.resize(to: current.size)
            }
            return .refused
        }
        // A window with a minimum size can end up larger than the tile, so it slides back onto the screen.
        if let settled = window.frame?.size {
            let origin = onScreenOrigin(for: settled, at: target.origin, in: area)
            if origin != target.origin {
                _ = window.move(to: origin)
            }
        }
        return .tiled
    }

    /// The area of the screen that holds the most of the window, or the first one when the window is on none of them.
    static func area(for window: CGRect, among screens: [CGRect]) -> CGRect? {
        let overlap = { (screen: CGRect) -> CGFloat in
            let shared = screen.intersection(window)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        let best = screens.max { overlap($0) < overlap($1) }
        return best.flatMap { overlap($0) > 0 ? $0 : nil } ?? screens.first
    }

    /// A screen's usable area in Accessibility's coordinates, from AppKit's, where y grows upward from the bottom of the main display.
    static func accessibilityArea(visibleFrame: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: visibleFrame.minX, y: mainDisplayHeight - visibleFrame.maxY, width: visibleFrame.width, height: visibleFrame.height)
    }

    private static func onScreenOrigin(for size: CGSize, at origin: CGPoint, in area: CGRect) -> CGPoint {
        CGPoint(
            x: max(area.minX, min(origin.x, area.maxX - size.width)),
            y: max(area.minY, min(origin.y, area.maxY - size.height))
        )
    }
}
