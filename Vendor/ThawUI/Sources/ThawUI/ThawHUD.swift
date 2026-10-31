//
//  ThawHUD.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// A small confirmation capsule under the menu bar, for verbs that otherwise
/// succeed invisibly.
///
/// Most actions carry their own feedback. A few do not: Zen mode toggled
/// from a hotkey, a Control Center button, a Shortcuts action applying a
/// profile with no window open. Without an acknowledgment the user presses
/// the key again to find out whether the first press landed.
///
/// The panel copies DisplayIdentifyOverlay deliberately, for the same
/// reasons. It is non-activating, because the hotkey was pressed inside
/// another app and that app keeps key. It sets ignoresMouseEvents, so clicks
/// pass through to whatever is underneath, including the menu bar the user
/// may be reaching for. It does not animate (animationBehavior = .none), so
/// it is Reduce Motion-safe by construction rather than by a branch that
/// could rot.
///
/// A single reused panel: a second show(symbol:text:) replaces the content
/// and restarts the timer, so a held hotkey never stacks capsules.
@MainActor
public enum ThawHUD {
    /// How tall the menu bar is on a screen. An app that can read it more exactly sets this.
    public static var menuBarHeight: (NSScreen) -> CGFloat = { screen in
        ThawHUDPlacement.menuBarHeight(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, fallback: NSStatusBar.system.thickness)
    }

    /// How long a confirmation stays up. Long enough to read two words after
    /// the eye moves to it, short enough that it is gone before it becomes
    /// something to dismiss.
    public static let duration: Duration = .milliseconds(1200)

    /// The live panel. Retained here because an NSPanel that nobody owns is
    /// released out from under its own dismissal.
    private static var panel: NSPanel?

    /// The in-flight dismissal, cancelled and replaced when a second HUD
    /// arrives before the previous one has expired.
    private static var dismissal: Task<Void, Never>?

    /// Shows a confirmation capsule and dismisses it after displayDuration.
    ///
    /// - Parameters:
    ///   - symbol: An SF Symbol name. It carries the verb at a glance, before
    ///     the text is read. Nil for text alone.
    ///   - text: What just happened, best in one to four words ("Zen on",
    ///     "Hidden items shown"). The capsule sizes to its text up to the
    ///     width of the screen and truncates past that.
    ///   - screen: The display to show the capsule on, or nil to follow the
    ///     pointer, where a gesture just happened. Event-driven callers pass
    ///     a screen because the event can land while the pointer is on
    ///     another display.
    ///   - placement: Where along the top of that display the capsule sits.
    ///     Confirmations use the center, where the eye already is.
    ///     Event-driven callers pass the user's choice, because an
    ///     unrequested banner in the center of a wide display covers the work.
    ///   - displayDuration: How long it stays up. A caller whose text runs to a
    ///     sentence gives it longer.
    public static func show(
        symbol: String? = nil,
        text: LocalizedStringResource,
        on screen: NSScreen? = nil,
        placement: ThawHUDPlacement = .center,
        displayDuration: Duration = ThawHUD.duration
    ) {
        dismissal?.cancel()

        guard let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return
        }

        let panel = panel ?? makePanel()
        Self.panel = panel

        let host = NSHostingView(rootView: ThawHUDCard(symbol: symbol, text: text))
        panel.contentView = host
        let frame = placement.frame(fitting: host.fittingSize, screenFrame: screen.frame, menuBarHeight: menuBarHeight(screen))
        panel.setFrame(frame, display: true)
        // Regardless of which app is active: a confirmation often arrives while another one is in front.
        panel.orderFrontRegardless()

        dismissal = Task {
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Tears the panel down. Idempotent, a cancelled dismissal that raced a
    /// second show simply finds nothing to close.
    public static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
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
        // Above ordinary windows and full-screen apps, below the menu bar
        // overlays Thaw itself drives, a confirmation annotates the desktop,
        // it is not menu bar chrome.
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
/// so it reads as Thaw's chrome rather than as an OS alert.
private struct ThawHUDCard: View {
    let symbol: String?
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(ThawType.symbol.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(ThawType.heading)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        // The width stays free so text wider than the screen truncates inside the capsule.
        .fixedSize(horizontal: false, vertical: true)
        .thawGlass(.panel, in: Capsule(style: .continuous))
        // The panel is non-activating and ignores the mouse; VoiceOver reaches
        // the same state through the settings pane and the menu bar itself.
        .accessibilityHidden(true)
    }
}
