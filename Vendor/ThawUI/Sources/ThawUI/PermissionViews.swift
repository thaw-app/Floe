//
//  PermissionViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import SwiftUI

// MARK: - PermissionPresentable

/// What the permission views need from an app's permission model. Checks and requests stay in the app.
@MainActor
public protocol PermissionPresentable {
    var titleText: Text { get }
    var iconName: String { get }
    var iconColor: Color { get }
    /// Whether the app needs this permission to work. Anything else carries the optional badge.
    var isRequired: Bool { get }
    var hasPermission: Bool { get }
    /// A shown system prompt went ungranted.
    var wasDeclined: Bool { get }
    var hasSettingsPane: Bool { get }
    func performRequest()
    func openSettingsPane()
}

// MARK: - PermissionStrings

/// The text of the permission views.
public nonisolated struct PermissionStrings: Sendable {
    public var optional: LocalizedStringResource
    public var granted: LocalizedStringResource
    public var grantAccess: LocalizedStringResource
    public var openSettings: LocalizedStringResource

    public init(
        optional: LocalizedStringResource,
        granted: LocalizedStringResource,
        grantAccess: LocalizedStringResource,
        openSettings: LocalizedStringResource
    ) {
        self.optional = optional
        self.granted = granted
        self.grantAccess = grantAccess
        self.openSettings = openSettings
    }
}

// MARK: - PermissionLabel

/// A permission's icon, name, and requirement badge.
///
/// Every surface that offers a permission names it the same way, down to the
/// badge wording. Only the type scale differs: onboarding sets its own so the
/// cards read as headings, while a settings row inherits the form's.
public struct PermissionLabel: View {
    /// Where the requirement badge sits.
    public enum BadgePlacement: Sendable {
        /// Directly after the title, so the two read as one phrase.
        case adjacent
        /// At the trailing edge of the available width.
        case trailing
        /// On its own line under the title. The card layout uses this: a
        /// narrow column turns a trailing badge into a long gap between the
        /// name and the tag, and an adjacent one crowds a heading that
        /// already wraps.
        case below
    }

    private let permission: any PermissionPresentable
    private let strings: PermissionStrings

    /// The title's font, or nil to inherit from the surrounding view.
    private let titleFont: Font?

    private let badgePlacement: BadgePlacement

    public init(
        permission: any PermissionPresentable,
        strings: PermissionStrings,
        titleFont: Font? = nil,
        badgePlacement: BadgePlacement = .adjacent
    ) {
        self.permission = permission
        self.strings = strings
        self.titleFont = titleFont
        self.badgePlacement = badgePlacement
    }

    public var body: some View {
        HStack(alignment: badgePlacement == .below ? .top : .center, spacing: 8) {
            // In the sidebar's box, so every permission's title starts in the same place.
            Image(systemName: permission.iconName)
                .font(ListStyle.symbolFont)
                .foregroundStyle(permission.iconColor)
                .frame(width: ListStyle.iconBox, height: ListStyle.iconBox)

            if badgePlacement == .below {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    badge
                }
            } else {
                title

                if badgePlacement == .trailing {
                    Spacer()
                }

                badge
            }
        }
    }

    private var title: some View {
        permission.titleText
            .font(titleFont)
    }

    @ViewBuilder
    private var badge: some View {
        if !permission.isRequired {
            ThawBadge(strings.optional)
        }
    }
}

// MARK: - PermissionStatusControl

/// A permission's state and the one control that changes it.
///
/// Granted is deliberately not a disabled button. A control that cannot be
/// pressed still reads as something the user is meant to press, and the whole
/// point of this state is that there is nothing left to do.
public struct PermissionStatusControl: View {
    /// How much room the control should take.
    public enum Layout: Sendable {
        /// Sits at the trailing edge of a settings row at the form's own scale.
        case inline
        /// Fills its container as a card's call to action.
        case filled
    }

    private let permission: any PermissionPresentable
    private let strings: PermissionStrings
    private let layout: Layout

    public init(
        permission: any PermissionPresentable,
        strings: PermissionStrings,
        layout: Layout = .inline
    ) {
        self.permission = permission
        self.strings = strings
        self.layout = layout
    }

    public var body: some View {
        switch layout {
        case .inline:
            if permission.hasPermission {
                Label {
                    Text(strings.granted)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
            } else {
                Button(requestTitle, action: request)
            }
        case .filled:
            if permission.hasPermission {
                Label {
                    Text(strings.granted)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(ThawType.detail.weight(.medium))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            } else {
                Button(action: request) {
                    Text(requestTitle)
                        .font(ThawType.detail.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.glass)
            }
        }
    }

    /// After a declined prompt macOS will not ask again, so the control leads to System Settings.
    private var offersSettings: Bool {
        permission.wasDeclined && permission.hasSettingsPane
    }

    var requestTitle: LocalizedStringResource {
        offersSettings ? strings.openSettings : strings.grantAccess
    }

    func request() {
        if offersSettings {
            permission.openSettingsPane()
        } else {
            permission.performRequest()
        }
    }
}
