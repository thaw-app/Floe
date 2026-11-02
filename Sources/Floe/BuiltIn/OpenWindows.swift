//
//  OpenWindows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices
import Synchronization

/// Unchecked for the reason MenuBarExtra is: the AXUIElement is an immutable reference Accessibility lets any thread use.
/// One window of a running app, read through the public Accessibility API.
nonisolated struct OpenWindow: Identifiable, @unchecked Sendable {
    let id: String
    let title: String
    let appName: String
    let appURL: URL?
    let pid: pid_t
    let isMinimized: Bool
    fileprivate let element: AXUIElement?

    init(id: String, title: String, appName: String, appURL: URL? = nil, pid: pid_t = 0, isMinimized: Bool = false, element: AXUIElement? = nil) {
        self.id = id
        self.title = title
        self.appName = appName
        self.appURL = appURL
        self.pid = pid
        self.isMinimized = isMinimized
        self.element = element
    }
}

/// A row of `windows`: a window, or the row that stands in for them until Floe may read them.
nonisolated enum WindowRow: Sendable {
    case window(OpenWindow)
    case access
}

nonisolated enum OpenWindows {
    static let keyword = "windows"
    /// The kinds of window a person switches to; panels, sheets and popovers are left out.
    private static let listedSubroles: Set = ["AXStandardWindow", "AXDialog"]

    /// Asks every app that has a Dock icon for its windows, all at once and off the main thread, as the menu bar scan does.
    static func scan() -> [OpenWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
        let found = Mutex<[Int: [OpenWindow]]>([:])
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let windows = windows(of: apps[index])
            if !windows.isEmpty {
                found.withLock { $0[index] = windows }
            }
        }
        // By app, in the order macOS lists them, so the list never depends on which app answered first.
        return found.withLock { byApp in byApp.keys.sorted().flatMap { byApp[$0] ?? [] } }
    }

    private static func windows(of app: NSRunningApplication) -> [OpenWindow] {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let windows: [AXUIElement] = value(application, kAXWindowsAttribute) else { return [] }
        let appName = app.localizedName ?? ""
        return windows.enumerated().compactMap { index, window in
            guard let subrole: String = value(window, kAXSubroleAttribute), listedSubroles.contains(subrole) else { return nil }
            let title: String? = value(window, kAXTitleAttribute)
            let isMinimized: Bool = value(window, kAXMinimizedAttribute) ?? false
            return OpenWindow(
                id: "\(app.processIdentifier):\(index)",
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? appName,
                appName: appName,
                appURL: app.bundleURL,
                pid: app.processIdentifier,
                isMinimized: isMinimized,
                element: window
            )
        }
    }

    /// Brings the window forward, out of the Dock first when it is minimized, and its app with it.
    @discardableResult
    static func focus(_ window: OpenWindow) -> Bool {
        guard let element = window.element else { return false }
        if window.isMinimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
        return raised
    }

    @discardableResult
    static func minimize(_ window: OpenWindow) -> Bool {
        guard let element = window.element else { return false }
        return AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// Presses the window's close button, so the app asks about unsaved changes as it would for a click.
    @discardableResult
    static func close(_ window: OpenWindow) -> Bool {
        guard let element = window.element, let button: AXUIElement = value(element, kAXCloseButtonAttribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
