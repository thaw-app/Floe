//
//  ThawUIWords+Permissions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

nonisolated extension PermissionStrings {
    static let floe = PermissionStrings(
        optional: "Optional",
        granted: "Granted",
        grantAccess: "Grant Access",
        openSettings: "Open System Settings"
    )
}

extension Permission: PermissionPresentable {
    /// Already localized when the permission was made.
    var titleText: Text {
        Text(title)
    }
}

extension PermissionLabel {
    init(permission: any PermissionPresentable, titleFont: Font? = nil, badgePlacement: BadgePlacement = .adjacent) {
        self.init(permission: permission, strings: .floe, titleFont: titleFont, badgePlacement: badgePlacement)
    }
}

extension PermissionStatusControl {
    init(permission: any PermissionPresentable, layout: Layout = .inline) {
        self.init(permission: permission, strings: .floe, layout: layout)
    }
}
