//
//  OnboardingPermissionsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: its button never waits for a grant, because Floe works without any,
//  and the permissions are rows in one panel instead of Thaw's cards, which have no room for four.

import AppKit
import SwiftUI
import ThawUI

/// The permission step of onboarding. Each card grants its own permission;
/// the page's button moves on whatever has been granted.
struct ThawPermissionsView: View {
    private let permissions: AppPermissions
    /// The button's title once nothing is left to grant.
    private let finishTitle: String
    private let onContinue: () -> Void

    @State private var appeared = false

    /// - Parameters:
    ///   - permissions: What is asked for, and what has been granted.
    ///   - finishTitle: The button's title once every permission is granted.
    ///   - onContinue: Called once the user has finished with the step.
    init(permissions: AppPermissions, finishTitle: String, onContinue: @escaping () -> Void) {
        self.permissions = permissions
        self.finishTitle = finishTitle
        self.onContinue = onContinue
    }

    private var continueTitle: String {
        switch permissions.permissionsState {
        case .hasAll: finishTitle
        case .missing: String(localized: "Continue Without Menu Bar Search", bundle: .floe)
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            VStack(spacing: 0) {
                ForEach(permissions.allPermissions) { permission in
                    if permission !== permissions.allPermissions.first {
                        Divider().padding(.leading, 50)
                    }
                    OnboardingPermissionRow(permission: permission)
                }
            }
            .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
            .padding(.horizontal, 30)

            privacyPanel

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    // Preflight only: continuing must never raise a prompt.
                    permissions.refreshPermissionsState()
                    onContinue()
                } label: {
                    Text(verbatim: continueTitle)
                        .font(ThawType.heading)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)

                Text("You can grant any of these later in Settings, under Privacy.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(permissions.hasEveryPermission ? 0 : 1)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .onAppear {
            // Preflight only: appearing must never raise a prompt.
            permissions.refreshPermissionsState()
            // A local curve because ThawMotion has no bouncy one.
            withThawAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 7) {
            Text("Allow access")
                .font(ThawType.display)
                .multilineTextAlignment(.center)

            Text("Each one switches on the feature named under it. The launcher and your extensions work without any of them.")
                .font(ThawType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            privacyFact("No analytics or usage tracking")
            privacyFact("Permission checks stay on your Mac")
            privacyFact("Open source under the AGPL, so you can read how it works")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .padding(.horizontal, 30)
    }

    private func privacyFact(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(ThawType.micro.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 1.5)

            Text(text)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingPermissionRow: View {
    let permission: Permission

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.iconName)
                .font(ThawType.display)
                .foregroundStyle(permission.iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(permission.title)
                        .font(ThawType.heading)
                    if !permission.isRequired {
                        ThawBadge("Optional")
                    }
                }
                Text(verbatim: permission.details.joined(separator: " "))
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            PermissionStatusControl(permission: permission)
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .thawAnimation(ThawMotion.settle, value: permission.hasPermission)
    }
}
