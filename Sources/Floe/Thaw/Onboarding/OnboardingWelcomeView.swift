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
        VStack(spacing: 0) {
            // Matched spacers center content; minimum spacing handles Larger Text with no spare height.
            Spacer(minLength: ThawSpacing.gutter)

            // The name with the icon beside it, as About shows them.
            identity

            copyBlock
                .padding(.top, ThawSpacing.inset)

            Button(action: onContinue) {
                Text("Continue")
                    .font(ThawType.heading)
                    .frame(minWidth: 140, minHeight: 34)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.top, ThawSpacing.section)

            Spacer(minLength: ThawSpacing.gutter)
        }
        .padding(.horizontal, ThawSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Offer a quiet exit before permissions so nobody has to sit through the setup.
        .overlay(alignment: .bottomTrailing) {
            Button(action: onSkip) {
                Text("Skip Setup")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close this window and start using \(AppInfo.displayName)")
            .padding(.trailing, ThawSpacing.gutter)
            .padding(.bottom, ThawSpacing.inset)
        }
        .background(VisualEffectBackground())
    }

    private var identity: some View {
        HStack(spacing: 12) {
            Text(verbatim: AppInfo.displayName)
                .font(.system(size: 48, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(Text("Welcome to \(AppInfo.displayName)", comment: "The placeholder is the name of this app."))
            // VoiceOver skips the decorative icon because the name beside it identifies the app.
            Image(nsImage: AboutSettingsPane.currentApplicationIcon())
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        }
    }

    /// Keep the reading sequence together so centering spacers move it as one block.
    private var copyBlock: some View {
        VStack(spacing: 0) {
            Text(
                "\(AppInfo.displayName) is a launcher for your apps and commands. It runs Raycast extensions and searches your menu bar.",
                comment: "The placeholder is the name of this app."
            )
            .font(ThawType.heading)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440)

            factsRow
                .padding(.top, ThawSpacing.gutter)
        }
    }

    /// Present pre-permission facts in one glanceable row.
    private var factsRow: some View {
        HStack(spacing: ThawSpacing.base) {
            fact(symbol: "lock.open", label: "Open source", spoken: "Free and open source")
            fact(symbol: "person.crop.circle.badge.xmark", label: "No sign-up", spoken: "No sign-up and no account")
            fact(symbol: "hand.raised", label: "No analytics or tracking", spoken: "No analytics, no tracking")
        }
        .frame(maxWidth: 520)
    }

    /// Scale a long label rather than wrapping one capsule taller than its neighbours.
    private func fact(symbol: String, label: LocalizedStringKey, spoken: LocalizedStringKey) -> some View {
        HStack(spacing: ThawSpacing.compact) {
            Image(systemName: symbol)
                .font(ThawType.symbol)
                .foregroundStyle(.secondary)

            Text(label)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, ThawSpacing.inset)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .thawGlass(.control, in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spoken))
    }
}
