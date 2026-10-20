//
//  OnboardingView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: the bento of menu bar demos is replaced by Floe's own tour, the
//  flow collects no choices so there is no outcome to hand back, and every screen can be skipped
//  because Floe works without any grant.

import SwiftUI
import ThawUI

/// Shared dimensions, sized for the tour's four rows of tiles.
enum ThawOnboardingWindowMetrics {
    static let width: CGFloat = 760
    static let height: CGFloat = 600
}

/// Ask for access after explaining its benefits; earlier screens need no grants and cannot fail for missing permissions.
struct ThawOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: OnboardingStep

    private let settings: AppSettings
    private let permissions: AppPermissions
    private let isReplay: Bool
    private let startsAtAccess: Bool
    private let onFinish: () -> Void

    /// - Parameters:
    ///   - isReplay: The user reopened the flow from Settings, so its last button closes it instead of opening Floe.
    ///   - startsAtAccess: Shows the access step alone, for a grant that went missing after the welcome was seen.
    ///   - onFinish: Called once when the user finishes or skips the flow.
    init(settings: AppSettings, permissions: AppPermissions, isReplay: Bool = false, startsAtAccess: Bool = false, onFinish: @escaping () -> Void) {
        self.settings = settings
        self.permissions = permissions
        self.isReplay = isReplay
        self.startsAtAccess = startsAtAccess
        _step = State(initialValue: startsAtAccess ? .access : .welcome)
        self.onFinish = onFinish
    }

    private var finishTitle: String {
        isReplay
            ? String(localized: "Done", bundle: .floe, comment: "The button that closes the welcome window.")
            : String(localized: "Open \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app.")
    }

    private func advance() {
        if let next = step.next {
            step = next
        } else {
            onFinish()
        }
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView(onContinue: advance, onSkip: onFinish)
                    .transition(.opacity)
            case .tour:
                OnboardingTourView(settings: settings, continueTitle: String(localized: "Continue", bundle: .floe, comment: "The button that goes to the next step of the welcome window."), onContinue: advance)
                    .transition(.opacity)
            case .access:
                ThawPermissionsView(permissions: permissions, finishTitle: finishTitle, onContinue: advance)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if !startsAtAccess, let progress = step.progress {
                OnboardingStepIndicator(step: progress.step, total: progress.total)
                    .padding(.top, ThawSpacing.inset)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .thawAnimation(ThawMotion.settle, value: step)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}
