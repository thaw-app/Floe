//
//  WindowManagement.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
import Foundation

/// Raycast's `WindowManagement` API, the parts that need no window. A desktop is a screen and the Space it
/// shows now, and a window's position counts from the top left of its desktop's usable area.
nonisolated enum WindowManagement {
    /// A screen and the Space on it. Its area is where windows go, in Accessibility's coordinates.
    struct Desktop: Equatable, Sendable {
        let display: CGDirectDisplayID
        let space: Int?
        let area: CGRect
        let isFullScreen: Bool
        var isActive = false

        /// Changes when the screen shows another Space, so a desktop read before the switch is no longer found.
        var id: String {
            "\(display)-\(space ?? 0)"
        }
    }

    /// A window as the API describes it, its frame in Accessibility's coordinates.
    struct Window: Sendable {
        let number: CGWindowID
        let application: [String: String]?
        let frame: CGRect
        let isFullScreen: Bool
        let canFullScreen: Bool
        let canResize: Bool
        let canMove: Bool
        let isActive: Bool
    }

    /// What an extension asks of WindowManagement, by the method the runtime sends.
    enum Request: Equatable, Sendable {
        case desktops
        case activeWindow
        case windowsOnActiveDesktop
        case setBounds(BoundsRequest)

        /// Nil for a method the API doesn't have, or a `setWindowBounds` that can't be read.
        init?(method: String, params: [String: Any]) {
            switch method {
            case "windowManagement.getDesktops": self = .desktops
            case "windowManagement.getActiveWindow": self = .activeWindow
            case "windowManagement.getWindowsOnActiveDesktop": self = .windowsOnActiveDesktop
            case "windowManagement.setWindowBounds":
                guard let bounds = BoundsRequest(params: params) else { return nil }
                self = .setBounds(bounds)
            default: return nil
            }
        }
    }

    /// What `setWindowBounds` does to the window.
    enum BoundsChange: Equatable, Sendable {
        /// A new frame on the desktop named, or the window's own. A part left out stays as it is.
        case frame(x: CGFloat?, y: CGFloat?, width: CGFloat?, height: CGFloat?, desktopID: String?)
        case fullScreen
    }

    /// What `setWindowBounds` asks of one window.
    struct BoundsRequest: Equatable, Sendable {
        let windowNumber: CGWindowID
        let change: BoundsChange

        /// Nil when the id is not a window number or the bounds are neither a frame nor "fullscreen".
        init?(params: [String: Any]) {
            guard let id = params["id"] as? String, let number = CGWindowID(id) else { return nil }
            windowNumber = number
            if params["bounds"] as? String == "fullscreen" {
                change = .fullScreen
                return
            }
            guard let bounds = params["bounds"] as? [String: Any] else { return nil }
            let position = bounds["position"] as? [String: Any]
            let size = bounds["size"] as? [String: Any]
            change = .frame(
                x: Self.number(position?["x"]),
                y: Self.number(position?["y"]),
                width: Self.number(size?["width"]),
                height: Self.number(size?["height"]),
                desktopID: params["desktopId"] as? String
            )
        }

        private static func number(_ value: Any?) -> CGFloat? {
            (value as? NSNumber).map { CGFloat($0.doubleValue) }
        }
    }

    /// Marks the active desktop: the one holding the focused window, else the one showing the Space the
    /// user is on, else the first.
    static func markingActive(_ desktops: [Desktop], focused: CGRect?, activeSpace: Int?) -> [Desktop] {
        let active = focused.flatMap { desktop(holding: $0, among: desktops) }
            ?? desktops.first { activeSpace != nil && $0.space == activeSpace }
            ?? desktops.first
        return desktops.map { desktop in
            var desktop = desktop
            desktop.isActive = desktop.display == active?.display
            return desktop
        }
    }

    /// The desktop that holds the most of a frame, or the first when it is on none.
    static func desktop(holding frame: CGRect, among desktops: [Desktop]) -> Desktop? {
        guard let area = WindowTiling.area(for: frame, among: desktops.map(\.area)) else { return nil }
        return desktops.first { $0.area == area }
    }

    /// The windows on the active desktop, in the order given.
    static func onActiveDesktop(_ windows: [Window], desktops: [Desktop]) -> [Window] {
        guard let active = desktops.first(where: \.isActive) else { return [] }
        return windows.filter { desktop(holding: $0.frame, among: desktops)?.display == active.display }
    }

    /// Where a frame change puts the window, in Accessibility's coordinates. A part left out keeps the
    /// window's size, or its place measured on its own desktop.
    static func target(x: CGFloat?, y: CGFloat?, width: CGFloat?, height: CGFloat?, from frame: CGRect, on own: CGRect, to area: CGRect) -> CGRect {
        CGRect(
            x: area.minX + (x ?? frame.minX - own.minX),
            y: area.minY + (y ?? frame.minY - own.minY),
            width: width ?? frame.width,
            height: height ?? frame.height
        )
    }

    /// A desktop as the API's `Desktop`.
    static func json(_ desktop: Desktop) -> [String: Any] {
        [
            "id": desktop.id,
            "screenId": String(desktop.display),
            "size": ["width": desktop.area.width, "height": desktop.area.height],
            "active": desktop.isActive,
            "type": desktop.isFullScreen ? "FullScreen" : "User",
        ]
    }

    /// A window as the API's `Window`, placed on the desktop that holds the most of it.
    static func json(_ window: Window, desktops: [Desktop]) -> [String: Any] {
        let desktop = desktop(holding: window.frame, among: desktops)
        let origin = desktop?.area.origin ?? .zero
        var json: [String: Any] = [
            "id": String(window.number),
            "desktopId": desktop?.id ?? "",
            "fullScreenSettable": window.canFullScreen,
            "resizable": window.canResize,
            "positionable": window.canMove,
            "active": window.isActive,
        ]
        json["bounds"] = window.isFullScreen ? "fullscreen" : [
            "position": ["x": window.frame.minX - origin.x, "y": window.frame.minY - origin.y],
            "size": ["width": window.frame.width, "height": window.frame.height],
        ]
        json["application"] = window.application
        return json
    }
}
