//
//  OnboardingPage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: a welcome reopened from Settings runs in the settings process, where Quit would end
//  that process alone, so its pages offer Close there instead.

import AppKit
import SwiftUI
import ThawUI

/// One screen of the onboarding window: its content, then a bar with the page's buttons in the app's
/// own styles, as Thaw's sheets lay them out. The content scrolls only when the page would be taller than the screen allows, so its buttons stay in reach.
struct OnboardingPage<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    /// The content's own height, measured inside the scroll view.
    @State private var contentHeight: CGFloat = 0

    /// What the window may give the content: the screen's visible height, less the title bar, the button bar and a margin.
    static func contentLimit(screenHeight: CGFloat?) -> CGFloat {
        max((screenHeight ?? 800) - 180, 240)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(ThawSpacing.section)
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, Self.contentLimit(screenHeight: NSScreen.main?.visibleFrame.height)))

            Divider()

            HStack(spacing: ThawSpacing.base) {
                footer
            }
            .buttonStyle(.settingsGlass)
            .padding(.horizontal, ThawSpacing.section)
            .padding(.vertical, ThawSpacing.gutter)
        }
        .frame(width: ThawOnboardingWindowMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectBackground())
    }
}

/// The button that moves the onboarding window on.
struct OnboardingContinueButton: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            title
        }
        .buttonStyle(.thawProminent)
        .keyboardShortcut(.defaultAction)
    }
}

/// How a page lets the window go without going on: Quit at the first launch, Close on a welcome reopened from Settings.
struct OnboardingLeaveButton: View {
    let isReplay: Bool
    /// What Quit leaves undone, for its help tag.
    let quitHelp: Text
    let close: () -> Void

    var body: some View {
        if isReplay {
            Button(action: close) {
                Text("Close", bundle: .floe, comment: "The button that closes the welcome window when it was opened again from Settings.")
            }
            .keyboardShortcut(.cancelAction)
        } else {
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app.")
            }
            .keyboardShortcut("q")
            .help(quitHelp)
        }
    }
}
