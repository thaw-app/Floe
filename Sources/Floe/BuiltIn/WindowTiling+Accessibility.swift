//
//  WindowTiling+Accessibility.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices

extension WindowTiling {
    /// Tiles the focused window of the app in front. Moving a window waits on its app, so that happens
    /// off the main thread. What goes wrong is said through say.
    static func tileFrontWindow(to tile: WindowTile, say: @escaping @MainActor (String) -> Void) {
        guard AXIsProcessTrusted() else {
            say(String(localized: "Tiling windows needs Accessibility access. Turn it on in System Settings.", bundle: .floe))
            return
        }
        guard let target = MenuItems.frontApp() else {
            say(Outcome.noWindow.message ?? "")
            return
        }
        let mainDisplayHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { accessibilityArea(visibleFrame: $0.visibleFrame, mainDisplayHeight: mainDisplayHeight) }
        let pid = target.pid
        AccessibilityWindow.queue.async {
            if let message = AccessibilityWindow.tileFocusedWindow(of: pid, to: tile, screens: screens).message {
                Task { @MainActor in say(message) }
            }
        }
    }
}

/// A window of another app, moved through the public Accessibility API.
nonisolated struct AccessibilityWindow: TilableWindow {
    private static let enhancedInterfaceAttribute = "AXEnhancedUserInterface"

    /// One move at a time, in the order they were asked for, so a quick second tile isn't undone by the first.
    static let queue = DispatchQueue(label: "floe.window-tiling", qos: .userInitiated)

    let element: AXUIElement

    static func tileFocusedWindow(of pid: pid_t, to tile: WindowTile, screens: [CGRect]) -> WindowTiling.Outcome {
        withApplication(pid) { application in
            guard let element: AXUIElement = OpenWindows.value(application, kAXFocusedWindowAttribute) else { return .noWindow }
            AXUIElementSetMessagingTimeout(element, 1)
            return WindowTiling.tile(AccessibilityWindow(element: element), to: tile, screens: screens)
        }
    }

    /// Runs body with the app's element, which answers within a second, while its enhanced interface is off.
    static func withApplication<T>(_ pid: pid_t, _ body: (AXUIElement) -> T) -> T {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 1)
        // While this is on, as it is for assistive tools, some apps animate a change of frame and
        // lose the second half of it, so it is off for the move.
        let enhanced: Bool = OpenWindows.value(application, enhancedInterfaceAttribute) ?? false
        if enhanced {
            AXUIElementSetAttributeValue(application, enhancedInterfaceAttribute as CFString, kCFBooleanFalse)
        }
        defer {
            // Screen readers rely on it in apps such as Chrome, so a write that fails is tried once more.
            if enhanced, !restoreEnhancedInterface(of: application) {
                _ = restoreEnhancedInterface(of: application)
            }
        }
        return body(application)
    }

    private static func restoreEnhancedInterface(of application: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(application, enhancedInterfaceAttribute as CFString, kCFBooleanTrue) == .success
    }

    var frame: CGRect? {
        guard let position: AXValue = OpenWindows.value(element, kAXPositionAttribute),
              let size: AXValue = OpenWindows.value(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    var isFullScreen: Bool {
        OpenWindows.value(element, "AXFullScreen") ?? false
    }

    func move(to origin: CGPoint) -> Bool {
        var origin = origin
        return set(kAXPositionAttribute, to: AXValueCreate(.cgPoint, &origin))
    }

    func resize(to size: CGSize) -> Bool {
        var size = size
        return set(kAXSizeAttribute, to: AXValueCreate(.cgSize, &size))
    }

    private func set(_ attribute: String, to value: AXValue?) -> Bool {
        guard let value else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }
}
