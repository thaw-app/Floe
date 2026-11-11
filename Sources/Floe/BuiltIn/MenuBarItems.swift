//
//  MenuBarItems.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices
import Synchronization

// Unchecked: every field is a value but the AXUIElement, an immutable reference to another app's
// element that Accessibility lets any thread use and CoreFoundation does not mark Sendable.
/// One item in the menu bar's status area. Thaw finds items through its own runtime; Floe reads them
/// through the public Accessibility API and opens one by pressing it.
nonisolated struct MenuBarExtra: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let ownerName: String
    let ownerURL: URL?
    /// Where the item sits, in global top-left-origin points (Accessibility's coordinates).
    let frame: CGRect
    fileprivate let element: AXUIElement

    init(id: String, name: String, ownerName: String, ownerURL: URL?, frame: CGRect, element: AXUIElement) {
        self.id = id
        self.name = name
        self.ownerName = ownerName
        self.ownerURL = ownerURL
        self.frame = frame
        self.element = element
    }
}

nonisolated enum MenuBarExtras {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// The value of `kAXTrustedCheckOptionPrompt`, which Swift imports as a mutable global.
    private static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"

    static func requestAccess() {
        AXIsProcessTrustedWithOptions([trustedCheckOptionPrompt: true] as CFDictionary)
    }

    /// Asks every running app for its extras menu bar, all at once: each answer is a round trip to that app,
    /// and most apps have none. Still off the main thread, since the slowest app sets the pace.
    static func scan() -> [MenuBarExtra] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID && MenuBarNaming.canOwnItems(executableURL: $0.executableURL)
        }
        let found = Mutex<[MenuBarExtra]>([])
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let extras = extras(of: apps[index])
            if !extras.isEmpty {
                found.withLock { $0 += extras }
            }
        }
        // Left to right, the order they sit in the menu bar. The name breaks a tie, so the order never depends on which app answered first.
        return found.withLock { $0 }.sorted { ($0.frame.minX, $0.id) < ($1.frame.minX, $1.id) }
    }

    private static func extras(of app: NSRunningApplication) -> [MenuBarExtra] {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let bar: AXUIElement = OpenWindows.value(application, "AXExtrasMenuBar"),
              let items: [AXUIElement] = OpenWindows.value(bar, kAXChildrenAttribute) else { return [] }
        let ownerName = app.localizedName ?? ""
        return items.enumerated().compactMap { index, item in
            let identifier: String? = OpenWindows.value(item, "AXIdentifier")
            let label = MenuBarNaming.label(
                title: OpenWindows.value(item, kAXTitleAttribute),
                description: OpenWindows.value(item, kAXDescriptionAttribute),
                help: OpenWindows.value(item, kAXHelpAttribute)
            )
            guard MenuBarNaming.isListed(identifier: identifier, label: label, ownerName: ownerName) else { return nil }
            let key = MenuBarNaming.identifier(
                bundleIdentifier: app.bundleIdentifier,
                ownerName: ownerName,
                identifier: identifier,
                label: label,
                index: index
            )
            return MenuBarExtra(id: key, name: label ?? ownerName, ownerName: ownerName, ownerURL: app.bundleURL, frame: frame(of: item), element: item)
        }
    }

    private static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let position: AXValue = OpenWindows.value(element, kAXPositionAttribute) {
            AXValueGetValue(position, .cgPoint, &origin)
        }
        if let extent: AXValue = OpenWindows.value(element, kAXSizeAttribute) {
            AXValueGetValue(extent, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    /// Opens the item's menu, the way a click on it would.
    @discardableResult
    static func open(_ extra: MenuBarExtra) -> Bool {
        AXUIElementPerformAction(extra.element, kAXPressAction as CFString) == .success
    }
}
