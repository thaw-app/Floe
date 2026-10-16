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
//  controller. It always has a close button, because nothing in Floe depends on finishing the flow.

import AppKit
import SwiftUI

/// The window that hosts onboarding.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    /// Shows the launcher once a first-launch flow ends. Set by the app delegate.
    var openLauncher: (() -> Void)?

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
            allPermissionsGranted: permissions.hasEveryPermission,
            hasUnanswered: permissions.hasUnanswered,
            replayRequested: replayRequested
        )
        switch stage {
        case let .onboarding(skipsAccessStep):
            present(skipsAccessStep: skipsAccessStep, isReplay: replayRequested)
        case .access:
            present(skipsAccessStep: false, isReplay: false, startsAtAccess: true)
        case .none:
            return false
        }
        return true
    }

    private func present(skipsAccessStep: Bool, isReplay: Bool, startsAtAccess: Bool = false) {
        window?.close()
        let size = NSSize(width: ThawOnboardingWindowMetrics.width, height: ThawOnboardingWindowMetrics.height)
        // Resizable so the window can grow with Larger Text instead of clipping it.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app.")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let view = ThawOnboardingView(settings: settings, permissions: permissions, skipsAccessStep: skipsAccessStep, isReplay: isReplay, startsAtAccess: startsAtAccess) { [weak self] in
            self?.finish(opensLauncher: !isReplay)
        }
        .frame(minWidth: size.width, idealWidth: size.width, minHeight: size.height, idealHeight: size.height)
        .ignoresSafeArea()
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(size)
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

    /// Closing counts as seen, whether by the last button, Skip Setup or the close button.
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
