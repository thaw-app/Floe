//
//  PermissionsWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: Floe has no SwiftUI scene, so the window is an NSWindow owned by a
//  controller, as tall as the page its hosting controller holds. It always has a close button, because
//  nothing in Floe depends on finishing the flow.

import AppKit
import SwiftUI
import ThawUI

/// The window that hosts onboarding.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    /// Shows the launcher once a first-launch flow ends. Set by the app delegate.
    var openLauncher: (() -> Void)?

    /// Opens Settings on the Quicklinks page and starts Import from Raycast. Each process that shows the window sets it.
    var importFromRaycast: (() -> Void)?

    /// Called after the window has closed. The settings process sets it: it stays alive while the welcome is open.
    var onClose: (() -> Void)?

    var isOpen: Bool {
        window != nil
    }

    private var window: NSWindow?
    private let settings: AppSettings
    private let permissions: AppPermissions

    init(settings: AppSettings, permissions: AppPermissions) {
        self.settings = settings
        self.permissions = permissions
    }

    /// Opens the window when the sequencer has something to show. Returns whether it did.
    @discardableResult
    func showIfNeeded(replayRequested: Bool = false) -> Bool {
        // Resolve the stage once per opening; the "seen" write must not change the screen under the user.
        permissions.refreshPermissionsState()
        let stage = OnboardingSequencer.stage(
            hasSeenOnboarding: settings.hasSeenOnboarding,
            hasUnanswered: permissions.hasUnanswered,
            replayRequested: replayRequested
        )
        switch stage {
        case .onboarding:
            present(isReplay: replayRequested)
        case .access:
            present(isReplay: false, startsAtAccess: true)
        case .none:
            return false
        }
        return true
    }

    /// The window for a page, as tall as the page and following it as the pages change: the hosting controller hands
    /// the page's own size to the window.
    static func makeWindow(for view: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: ThawOnboardingWindowMetrics.width, height: 400)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let controller = NSHostingController(rootView: view.thawTheme(.floe))
        controller.sizingOptions = [.preferredContentSize]
        window.contentViewController = controller
        return window
    }

    private func present(isReplay: Bool, startsAtAccess: Bool = false) {
        window?.close()
        let view = ThawOnboardingView(
            settings: settings,
            permissions: permissions,
            isReplay: isReplay,
            startsAtAccess: startsAtAccess,
            importFromRaycast: { [weak self] in self?.importFromRaycast?() },
            onFinish: { [weak self] in self?.finish(opensLauncher: !isReplay) },
            onClose: { [weak self] in self?.finish(opensLauncher: false) }
        )
        .ignoresSafeArea()
        // Light or Dark from the Settings theme. Black's background is for Settings, so this window keeps its own.
        .heldToSettingsTheme(settings)
        // Glass buttons are capsules here too, as in Settings.
        .buttonBorderShape(.capsule)
        let window = Self.makeWindow(for: view)
        window.title = String(localized: "Welcome to \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app.")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.delegate = self
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(opensLauncher: Bool) {
        window?.close()
        if opensLauncher {
            openLauncher?()
        }
    }

    /// Closing counts as seen, whether by the last button, Close or the close button.
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        window = nil
        defer { onClose?() }
        permissions.refreshPermissionsState()
        permissions.declineUngranted()
        guard !settings.hasSeenOnboarding else { return }
        settings.hasSeenOnboarding = true
        settings.save()
    }
}
