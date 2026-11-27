//
//  OnboardingView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: the flow collects no choices so there is no outcome to hand back, and
//  its button never waits for a grant, because Floe works without any.

import SwiftUI
import ThawUI

/// The window is this wide and as tall as the page it shows.
enum ThawOnboardingWindowMetrics {
    static let width: CGFloat = 520
}

/// Welcome, then access, then how to use Floe. Recovery, for a grant that went missing, is the access page alone.
struct ThawOnboardingView: View {
    @State private var step: OnboardingStep

    private let settings: AppSettings
    private let permissions: AppPermissions
    private let isReplay: Bool
    private let startsAtAccess: Bool
    private let importFromRaycast: () -> Void
    private let onFinish: () -> Void
    private let onClose: () -> Void

    /// - Parameters:
    ///   - isReplay: The user reopened the flow from Settings, so its last button closes it instead of opening Floe.
    ///   - startsAtAccess: Shows the access step alone, for a grant that went missing after the welcome was seen.
    ///   - importFromRaycast: Opens Settings and starts Import from Raycast, for the last page's button.
    ///   - onFinish: Called once when the user finishes the flow.
    ///   - onClose: Closes the window without finishing, for a welcome opened from Settings.
    init(
        settings: AppSettings,
        permissions: AppPermissions,
        isReplay: Bool = false,
        startsAtAccess: Bool = false,
        importFromRaycast: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.settings = settings
        self.permissions = permissions
        self.isReplay = isReplay
        self.startsAtAccess = startsAtAccess
        self.importFromRaycast = importFromRaycast
        self.onFinish = onFinish
        self.onClose = onClose
        _step = State(initialValue: startsAtAccess ? .access : .welcome)
    }

    private var finishTitle: String {
        isReplay
            ? String(localized: "Done", bundle: .floe, comment: "The button that closes the welcome window.")
            : String(localized: "Open \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app.")
    }

    private func advance() {
        // Recovery is the access page alone.
        if let next = step.next, !startsAtAccess {
            step = next
        } else {
            onFinish()
        }
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView(isReplay: isReplay, onContinue: advance, onClose: onClose)
                    .transition(.opacity)
            case .access:
                ThawPermissionsView(
                    permissions: permissions, isReplay: isReplay, finishTitle: startsAtAccess ? finishTitle : nil, onContinue: advance, onClose: onClose
                )
                .transition(.opacity)
            case .done:
                OnboardingDoneView(settings: settings, finishTitle: finishTitle, importFromRaycast: importFromRaycast, onFinish: advance)
                    .transition(.opacity)
            }
        }
        .onboardingStepAnimation(value: step)
    }
}
