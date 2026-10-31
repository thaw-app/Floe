//
//  OnboardingWelcomeView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: the copy describes Floe, and the quiet exit skips the setup
//  instead of quitting, because Floe is usable without it.

import AppKit
import SwiftUI
import ThawUI

/// Capsules fit or scale uneven label lengths, with fuller claims in accessibility labels; matched spacers center the stack.
struct OnboardingWelcomeView: View {
    var onContinue: () -> Void
    var onSkip: () -> Void

    var body: some View {
        OnboardingWelcomeLayout(
            continueTitle: Text("Continue", bundle: .floe),
            onContinue: onContinue
        ) {
            identity
        } copy: {
            copyBlock
        } exit: {
            OnboardingQuietButton(
                title: Text("Skip Setup", bundle: .floe),
                help: Text("Close this window and start using \(AppInfo.displayName)", bundle: .floe),
                action: onSkip
            )
        }
    }

    private var identity: some View {
        HStack(spacing: ThawSpacing.inset) {
            Text(verbatim: AppInfo.displayName)
                .font(.system(size: 48, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(Text("Welcome to \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app."))
            // VoiceOver skips the decorative icon because the name beside it identifies the app.
            Image(nsImage: AboutSettingsPane.currentApplicationIcon())
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        }
    }

    /// The reading sequence under the name: what Floe is, then one glanceable row of facts.
    @ViewBuilder private var copyBlock: some View {
        Text(
            "\(AppInfo.displayName) is a launcher for your apps and commands. It runs Raycast extensions and searches your menu bar.",
            bundle: .floe,
            comment: "The placeholder is the name of this app."
        )
        .font(ThawType.heading)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 440)

        OnboardingFactRow(maxWidth: 520) {
            OnboardingFactCapsule(symbol: "lock.open", label: Text("Open source", bundle: .floe), spoken: Text("Free and open source", bundle: .floe))
            OnboardingFactCapsule(symbol: "person.crop.circle.badge.xmark", label: Text("No sign-up", bundle: .floe), spoken: Text("No sign-up and no account", bundle: .floe))
            OnboardingFactCapsule(symbol: "hand.raised", label: Text("No analytics or tracking", bundle: .floe), spoken: Text("No analytics, no tracking", bundle: .floe))
        }
        .padding(.top, ThawSpacing.gutter)
    }
}
