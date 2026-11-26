//
//  OnboardingPermissionsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: its button never waits for a grant, because Floe works without any, and both
//  onboarding and recovery list every permission, the one menu bar search needs apart from the others.

import AppKit
import SwiftUI
import ThawUI

/// The permissions as one list, for onboarding and for the recovery screen shown when a grant went missing.
/// Each row grants its own permission; the page's button moves on whatever has been granted.
struct ThawPermissionsView: View {
    private let permissions: AppPermissions
    private let isReplay: Bool
    /// The button's title when this is the last page: recovery, which shows this page alone.
    private let finishTitle: String?
    private let onContinue: () -> Void
    private let onClose: () -> Void

    /// - Parameters:
    ///   - permissions: What is asked for, and what has been granted.
    ///   - isReplay: The welcome was opened again from Settings.
    ///   - finishTitle: The button's title when this page ends the flow; nil when a page follows.
    ///   - onContinue: Called once the user has finished with the step.
    ///   - onClose: Closes the window, for a welcome opened from Settings.
    init(permissions: AppPermissions, isReplay: Bool = false, finishTitle: String? = nil, onContinue: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.permissions = permissions
        self.isReplay = isReplay
        self.finishTitle = finishTitle
        self.onContinue = onContinue
        self.onClose = onClose
    }

    /// The step's button. Without Accessibility Floe still works, so it moves on and says what is left out.
    static func continueTitle(state: AppPermissions.PermissionsState, finishTitle: String?) -> String {
        switch state {
        case .hasAll: finishTitle ?? String(localized: "Continue", bundle: .floe, comment: "The button that goes to the next page of the welcome window.")
        case .missing: String(localized: "Continue Without Accessibility", bundle: .floe, comment: "The button that leaves the permission step while Accessibility is not granted.")
        }
    }

    var body: some View {
        OnboardingPage {
            VStack(spacing: ThawSpacing.gutter) {
                OnboardingHeader(
                    title: Text("Allow access", bundle: .floe),
                    message: Text(
                        "The launcher and your extensions work without any of these. Nothing is asked until you click Grant Access, and the checks stay on your Mac.",
                        bundle: .floe
                    )
                )

                VStack(alignment: .leading, spacing: ThawSpacing.compact) {
                    groupTitle(Text("For menu bar search", bundle: .floe, comment: "Above the permission that menu bar search needs, in the welcome window."))
                    PermissionList(permissions: permissions.allPermissions.filter(\.isRequired))
                    groupTitle(Text("For other features", bundle: .floe, comment: "Above the optional permissions in the welcome window."))
                        .padding(.top, ThawSpacing.base)
                    PermissionList(permissions: permissions.allPermissions.filter { !$0.isRequired })
                }
            }
        } footer: {
            OnboardingLeaveButton(
                isReplay: isReplay,
                quitHelp: Text("Quit \(AppInfo.displayName) without granting access", bundle: .floe, comment: "The placeholder is the name of this app."),
                close: onClose
            )
            Spacer(minLength: ThawSpacing.base)
            OnboardingContinueButton(title: Text(verbatim: Self.continueTitle(state: permissions.permissionsState, finishTitle: finishTitle))) {
                // Preflight only: continuing must never raise a prompt.
                permissions.refreshPermissionsState()
                onContinue()
            }
        }
        .onAppear {
            // Preflight only: appearing must never raise a prompt.
            permissions.refreshPermissionsState()
        }
    }

    private func groupTitle(_ title: Text) -> some View {
        title
            .font(ThawType.sublabel.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.leading, ThawSpacing.inset)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Permissions as rows in one rounded group, as a grouped form draws them.
private struct PermissionList: View {
    let permissions: [Permission]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                if index > 0 {
                    Divider()
                        .padding(.leading, ThawSpacing.inset + 24 + ThawSpacing.inset)
                }
                PermissionRow(permission: permission)
            }
        }
        .onboardingCard()
    }
}

/// A permission's name, what it is for, and its Grant Access button or granted mark.
private struct PermissionRow: View {
    let permission: Permission

    var body: some View {
        HStack(spacing: ThawSpacing.inset) {
            Image(systemName: permission.iconName)
                .font(ThawType.sidebarSymbol)
                .foregroundStyle(permission.iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text(permission.title)
                    .font(ThawType.label)
                Text((try? AttributedString(markdown: permission.rowSubtitle)) ?? AttributedString(permission.rowSubtitle))
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if permission.isWaitingForGrant, !permission.awaitingPromptAnswer {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Waiting for access", bundle: .floe))
                    .transition(.opacity)
            }

            control
                .buttonStyle(.settingsGlass)
                .fixedSize()
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
        .accessibilityElement(children: .contain)
        .thawAnimation(ThawMotion.settle, value: permission.requestState)
        .symbolEffect(.bounce, value: permission.hasPermission)
    }

    /// Hidden rather than removed while a prompt is up, so the row keeps its width.
    private var control: some View {
        let waiting = permission.awaitingPromptAnswer
        return PermissionStatusControl(permission: permission)
            .opacity(waiting ? 0 : 1)
            .allowsHitTesting(!waiting)
            .accessibilityHidden(waiting)
            .overlay(alignment: .trailing) {
                if waiting {
                    HStack(spacing: ThawSpacing.compact) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting…", bundle: .floe, comment: "Beside a permission while macOS asks for it.")
                            .font(ThawType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .transition(.opacity)
                }
            }
    }
}
