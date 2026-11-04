//
//  WindowManagement+System.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices

/// The window server's number for an Accessibility window. HIServices exports it without declaring it.
@_silgen_name("_AXUIElementGetWindow")
private nonisolated func axUIElementGetWindow(_ element: AXUIElement, _ number: UnsafeMutablePointer<CGWindowID>) -> AXError

/// The WindowManagement requests, answered from the screens, the window server's list and Accessibility.
nonisolated extension WindowManagement {
    @concurrent
    static func answer(_ request: Request) async throws -> Any {
        guard AXIsProcessTrusted() else {
            throw RequestRefusal(errorDescription: String(localized: "Floe needs Accessibility access to manage windows. Turn it on in System Settings.", bundle: .floe))
        }
        switch request {
        case .desktops: return await desktops()
        case .activeWindow: return try await activeWindow()
        case .windowsOnActiveDesktop: return await windowsOnActiveDesktop()
        case let .setBounds(bounds): return try await setBounds(bounds)
        }
    }

    private static func desktops() async -> Any {
        let focused = WindowReader.focusedWindow()?.frame
        return await currentDesktops(focused: focused).map(json)
    }

    private static func activeWindow() async throws -> Any {
        guard let window = WindowReader.focusedWindow() else {
            throw RequestRefusal(errorDescription: String(localized: "No window is active.", bundle: .floe, comment: "Said to an extension that asked for the active window when there is none."))
        }
        return await json(window, desktops: currentDesktops(focused: window.frame))
    }

    private static func windowsOnActiveDesktop() async -> Any {
        let focused = WindowReader.focusedWindow()
        let desktops = await currentDesktops(focused: focused?.frame)
        let windows = WindowReader.onScreenWindows(focused: focused?.number)
        return onActiveDesktop(windows, desktops: desktops).map { json($0, desktops: desktops) }
    }

    private static func setBounds(_ request: BoundsRequest) async throws -> Any {
        let desktops = await currentDesktops(focused: nil)
        let outcome = await withCheckedContinuation { continuation in
            AccessibilityWindow.queue.async {
                continuation.resume(returning: WindowReader.apply(request, desktops: desktops))
            }
        }
        if let refusal = outcome {
            throw RequestRefusal(errorDescription: refusal)
        }
        return NSNull()
    }

    @MainActor
    private static func currentDesktops(focused: CGRect?) -> [Desktop] {
        let mainDisplayHeight = NSScreen.screens.first?.frame.height ?? 0
        let desktops = NSScreen.screens.compactMap { screen -> Desktop? in
            guard let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            let space = WindowServerSpaces.currentSpace(on: display)
            return Desktop(
                display: display,
                space: space,
                area: WindowTiling.accessibilityArea(visibleFrame: screen.visibleFrame, mainDisplayHeight: mainDisplayHeight),
                isFullScreen: space.map(WindowServerSpaces.isFullScreen) ?? false
            )
        }
        return markingActive(desktops, focused: focused, activeSpace: WindowServerSpaces.activeSpace())
    }
}

/// Reads windows of other apps through Accessibility, and moves one.
private nonisolated enum WindowReader {
    /// The focused window of the app in front, which is never Floe: its panel doesn't make Floe active.
    static func focusedWindow() -> WindowManagement.Window? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let element: AXUIElement = OpenWindows.value(application, kAXFocusedWindowAttribute) else { return nil }
        return describe(element, of: app, isActive: true)
    }

    /// Every standard window on the Spaces shown now, front to back, from the window server's on-screen list.
    static func onScreenWindows(focused: CGWindowID?) -> [WindowManagement.Window] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let listed = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let order = listed.compactMap { info -> (number: CGWindowID, pid: pid_t)? in
            guard info[kCGWindowLayer as String] as? Int == 0, let number = info[kCGWindowNumber as String] as? CGWindowID, let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID
            else { return nil }
            return (number, pid)
        }
        var described: [CGWindowID: WindowManagement.Window] = [:]
        for pid in Set(order.map(\.pid)) {
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            for element in elements(of: pid) {
                guard let number = number(of: element), let window = describe(element, of: app, isActive: number == focused) else { continue }
                described[number] = window
            }
        }
        return order.compactMap { described[$0.number] }
    }

    /// Moves, sizes or fills the screen with one window. Nil when that worked, else why not.
    static func apply(_ request: WindowManagement.BoundsRequest, desktops: [WindowManagement.Desktop]) -> String? {
        guard let pid = owner(of: request.windowNumber) else { return noWindow(request.windowNumber) }
        return AccessibilityWindow.withApplication(pid) { application in
            guard let element = elements(of: application).first(where: { number(of: $0) == request.windowNumber }) else {
                return noWindow(request.windowNumber)
            }
            AXUIElementSetMessagingTimeout(element, 1)
            let window = AccessibilityWindow(element: element)
            switch request.change {
            case .fullScreen:
                guard settable(element, "AXFullScreen"), AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, kCFBooleanTrue) == .success
                else { return String(localized: "This window can't go full screen.", bundle: .floe) }
                return nil
            case let .frame(x, y, width, height, desktopID):
                guard !window.isFullScreen else { return WindowTiling.Outcome.fullScreen.message }
                guard let frame = window.frame, let own = WindowManagement.desktop(holding: frame, among: desktops) else {
                    return noWindow(request.windowNumber)
                }
                let destination = desktopID.map { id in desktops.first { $0.id == id } } ?? own
                guard let destination else {
                    return String(localized: "No desktop with the id \(desktopID ?? "") is shown now.", bundle: .floe, comment: "Said to an extension. The placeholder is the desktop id it gave.")
                }
                let target = WindowManagement.target(x: x, y: y, width: width, height: height, from: frame, on: own.area, to: destination.area)
                return WindowTiling.place(window, at: target, from: frame, in: destination.area).message
            }
        }
    }

    private static func noWindow(_ number: CGWindowID) -> String {
        String(localized: "No window with the id \(String(number)) is open.", bundle: .floe, comment: "Said to an extension. The placeholder is the window id it gave.")
    }

    private static func describe(_ element: AXUIElement, of app: NSRunningApplication, isActive: Bool) -> WindowManagement.Window? {
        AXUIElementSetMessagingTimeout(element, 1)
        guard let number = number(of: element), let frame = AccessibilityWindow(element: element).frame else { return nil }
        return WindowManagement.Window(
            number: number,
            application: app.bundleURL.map { HostRequest.application(at: $0, name: app.localizedName) },
            frame: frame,
            isFullScreen: OpenWindows.value(element, "AXFullScreen") ?? false,
            canFullScreen: settable(element, "AXFullScreen"),
            canResize: settable(element, kAXSizeAttribute),
            canMove: settable(element, kAXPositionAttribute),
            isActive: isActive
        )
    }

    /// The app's standard windows and dialogs, as Open Windows lists them.
    private static func elements(of pid: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        return elements(of: application)
    }

    private static func elements(of application: AXUIElement) -> [AXUIElement] {
        let windows: [AXUIElement] = OpenWindows.value(application, kAXWindowsAttribute) ?? []
        return windows.filter { window in
            let subrole: String? = OpenWindows.value(window, kAXSubroleAttribute)
            return subrole.map(OpenWindows.listedSubroles.contains) ?? false
        }
    }

    private static func number(of element: AXUIElement) -> CGWindowID? {
        var number: CGWindowID = 0
        return axUIElementGetWindow(element, &number) == .success && number != 0 ? number : nil
    }

    private static func owner(of number: CGWindowID) -> pid_t? {
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String: Any]]
        return info?.first?[kCGWindowOwnerPID as String] as? pid_t
    }

    private static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }
}
