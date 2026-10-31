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
//  and the cards sit in two rows, the Mac's permissions over your data's, with one line each.

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
        case .missing: String(localized: "Continue Without Accessibility", bundle: .floe, comment: "The button that leaves the permission step while Accessibility is not granted.")
        }
    }

    var body: some View {
        VStack(spacing: ThawSpacing.inset) {
            header
                .padding(.top, ThawSpacing.section)

            VStack(spacing: ThawSpacing.gutter) {
                cardRow(Array(permissions.allPermissions.prefix(Self.firstRowCount)))
                cardRow(Array(permissions.allPermissions.dropFirst(Self.firstRowCount)))
            }
            .padding(.horizontal, ThawSpacing.section)

            privacyPanel

            Spacer(minLength: 0)

            HStack(spacing: ThawSpacing.gutter) {
                Text("You can grant any of these later in Settings, under Privacy.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .opacity(permissions.hasEveryPermission ? 0 : 1)
                Spacer()
                OnboardingPrimaryButton {
                    // Preflight only: continuing must never raise a prompt.
                    permissions.refreshPermissionsState()
                    onContinue()
                } label: {
                    Text(verbatim: continueTitle)
                }
            }
            .padding(.horizontal, ThawSpacing.section)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .onAppear {
            // Preflight only: appearing must never raise a prompt.
            permissions.refreshPermissionsState()
        }
    }

    /// Accessibility and the other permissions of the Mac itself; Calendar, Reminders and Contacts follow.
    private static let firstRowCount = 4

    private func cardRow(_ row: [Permission]) -> some View {
        HStack(alignment: .top, spacing: ThawSpacing.gutter) {
            ForEach(row) { permission in
                PermissionCard(permission: permission)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        OnboardingHeader(
            title: Text("Allow access", bundle: .floe),
            message: Text("Each card says what its permission switches on. The launcher and your extensions work without any of them.", bundle: .floe)
        )
    }

    private var privacyPanel: some View {
        HStack(spacing: 18) {
            // About the permissions alone: the welcome before this already said open source and no tracking.
            privacyFact("Nothing is asked until you click Grant Access")
            privacyFact("Permission checks stay on your Mac")
            privacyFact("Turn any off later in System Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .onboardingCard()
        .padding(.horizontal, ThawSpacing.section)
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

/// One permission as a card: its name, one line on what it switches on, and the button that asks for it.
private struct PermissionCard: View {
    let permission: Permission

    var body: some View {
        OnboardingPermissionCard(surface: .flat, spacing: 8, isGranted: permission.hasPermission) {
            HStack(spacing: ThawSpacing.compact) {
                OnboardingIconTile(symbol: permission.iconName, tint: permission.iconColor)
                Text(permission.title)
                    .font(ThawType.heading)
                    .lineLimit(1)
                    // The window is narrow enough that a long name shrinks a little rather than being cut.
                    .minimumScaleFactor(0.8)
            }
        } details: {
            Text((try? AttributedString(markdown: permission.summary)) ?? AttributedString(permission.summary))
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } control: {
            PermissionStatusControl(permission: permission, layout: .filled)
        }
    }
}
