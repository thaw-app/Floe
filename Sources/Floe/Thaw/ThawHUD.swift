//
//  ThawHUD.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3. The symbol is optional because extensions send text only, the text
//  is a plain string, the capsule stays up a little longer because extensions write full sentences,
//  and the frame math lives in ThawHUDPlacement.

import AppKit
import SwiftUI
import ThawUI

/// A small confirmation capsule under the menu bar, for actions that otherwise
/// succeed invisibly.
///
/// Most actions carry their own feedback. A few do not: an extension's showHUD
/// after the launcher has closed, a favorite toggled from the keyboard, a
/// background command that failed. Without an acknowledgment the user repeats
/// the action to find out whether it landed.
///
/// The panel is non-activating, because the action often ends with another app
/// in front and that app keeps key. It sets ignoresMouseEvents, so clicks pass
/// through to whatever is underneath, including the menu bar the user may be
/// reaching for. It does not animate (animationBehavior = .none), so it is
/// safe under Reduce Motion without a branch for it.
///
/// A single reused panel: a second show(symbol:text:) replaces the content
/// and restarts the timer, so repeated actions never stack capsules.
@MainActor
enum ThawHUD {
    /// How long a confirmation stays up. Thaw uses 1.2 seconds for two-word labels;
    /// extension messages are sentences, so Floe keeps the 1.6 seconds its HUD always had.
    static let duration: Duration = .milliseconds(1600)

    /// The live panel. Retained here because an NSPanel that nobody owns is
    /// released out from under its own dismissal.
    private static var panel: NSPanel?

    /// The in-flight dismissal, cancelled and replaced when a second HUD
    /// arrives before the previous one has expired.
    private static var dismissal: Task<Void, Never>?

    /// Shows a confirmation capsule and dismisses it after duration.
    ///
    /// - Parameters:
    ///   - symbol: An SF Symbol name shown before the text, or nil for text alone.
    ///   - text: What just happened. The capsule sizes to its text, up to the
    ///     width of the screen, and truncates past that.
    ///   - screen: The display to show the capsule on, or nil to follow the
    ///     pointer, where the action just happened.
    ///   - placement: Where along the top of that display the capsule sits.
    static func show(
        symbol: String? = nil,
        text: String,
        on screen: NSScreen? = nil,
        placement: ThawHUDPlacement = .center
    ) {
        dismissal?.cancel()

        guard let screen = screen ?? screenWithMouse ?? NSScreen.main else {
            return
        }

        let panel = panel ?? makePanel()
        Self.panel = panel

        let host = NSHostingView(rootView: ThawHUDCard(symbol: symbol, text: text))
        panel.contentView = host
        let menuBarHeight = ThawHUDPlacement.menuBarHeight(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            fallback: NSStatusBar.system.thickness
        )
        let frame = placement.frame(fitting: host.fittingSize, screenFrame: screen.frame, menuBarHeight: menuBarHeight)
        panel.setFrame(frame, display: true)
        // Thaw calls orderFront; Floe is often not the active app when a HUD arrives, so it asks regardless.
        panel.orderFrontRegardless()

        dismissal = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Tears the panel down. Idempotent, a cancelled dismissal that raced a
    /// second show simply finds nothing to close.
    static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// The screen the pointer is on. Thaw has this as an NSScreen extension.
    private static var screenWithMouse: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above ordinary windows, the launcher and full-screen apps.
        panel.level = .statusBar
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        // A label, never a target: clicks fall through to whatever is behind.
        panel.ignoresMouseEvents = true
        return panel
    }
}

/// The capsule itself: an optional symbol beside text, on the shared panel glass
/// so it reads as part of the launcher instead of as an OS alert.
private struct ThawHUDCard: View {
    let symbol: String?
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(ThawType.symbol.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: text)
                .font(ThawType.heading)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        // Thaw fixes the size to the text. Floe leaves the width free so text wider than the
        // screen truncates inside the capsule; the height stays fixed.
        .fixedSize(horizontal: false, vertical: true)
        .thawGlass(.panel, in: Capsule(style: .continuous))
        // The panel is non-activating and ignores the mouse, so VoiceOver cannot reach it.
        .accessibilityHidden(true)
    }
}
