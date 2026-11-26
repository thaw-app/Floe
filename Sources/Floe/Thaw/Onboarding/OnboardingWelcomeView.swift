//
//  OnboardingWelcomeView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: the copy and the terms describe Floe.

import AppKit
import SwiftUI
import ThawUI

/// The app's name and one sentence on what it does, with its terms.
struct OnboardingWelcomeView: View {
    var isReplay = false
    var onContinue: () -> Void
    var onClose: () -> Void

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                // VoiceOver skips the decorative icon because the title identifies the app.
                Image(nsImage: AboutSettingsPane.currentApplicationIcon())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .thawShadow(.hero)
                    .accessibilityHidden(true)

                Text("Welcome to \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app.")
                    .font(ThawType.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, ThawSpacing.inset)

                Text(
                    "\(AppInfo.displayName) is a launcher for your apps and commands. It runs Raycast extensions and searches your menu bar.",
                    bundle: .floe,
                    comment: "The placeholder is the name of this app."
                )
                .font(ThawType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
                .padding(.top, ThawSpacing.compact)

                Text("Free under AGPL-3.0, with no tracking and no account.", bundle: .floe, comment: "AGPL-3.0 is the name of a license.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThawSpacing.gutter)
            }
        } footer: {
            // Before permissions, so an accidental launch needs no setup.
            OnboardingLeaveButton(
                isReplay: isReplay,
                quitHelp: Text("Quit \(AppInfo.displayName) without setting it up", bundle: .floe, comment: "The placeholder is the name of this app."),
                close: onClose
            )
            Spacer()
            OnboardingContinueButton(title: Text("Continue", bundle: .floe, comment: "The button that goes to the next page of the welcome window."), action: onContinue)
        }
    }
}
