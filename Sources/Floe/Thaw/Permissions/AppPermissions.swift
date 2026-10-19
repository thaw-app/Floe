//
//  AppPermissions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: Floe needs only Accessibility, so the Screen Recording,
//  Full Disk Access and Control Center grants, the diagnostics log and the preview protocol are
//  left out. The optional permissions are Floe's. Both are injectable for tests.

import Foundation

/// A type that manages the permissions of the app.
@MainActor
@Observable
final class AppPermissions {
    static let shared = AppPermissions(decisions: .shared)

    /// The state of the app's granted permissions.
    enum PermissionsState: Equatable {
        /// At least one permission that menu bar search needs hasn't been granted.
        case missing
        /// Every permission menu bar search needs has been granted.
        case hasAll
    }

    /// The permission for Accessibility features.
    let accessibility: Permission

    /// The optional ones, each for one feature: Screen Recording, the home folders, notifications, Calendar, Reminders and Contacts.
    let others: [Permission]
    private let decisions: PermissionDecisions?

    private var ungranted: Set<String> {
        Set(allPermissions.filter { !$0.hasPermission }.map(\.key))
    }

    var hasUnanswered: Bool {
        decisions?.hasUnanswered(ungranted) ?? !ungranted.isEmpty
    }

    func declineUngranted() {
        decisions?.decline(ungranted)
    }

    /// Fired after any permission's granted state transitions, for owners
    /// that must react to a specific grant.
    @ObservationIgnored
    var onPermissionTransition: ((Permission, Bool) -> Void)?

    /// The state of the app's granted permissions.
    private(set) var permissionsState: PermissionsState = .missing

    /// Every permission Floe can use.
    var allPermissions: [Permission] {
        [accessibility] + others
    }

    /// Whether nothing is left to grant, the optional ones included.
    var hasEveryPermission: Bool {
        allPermissions.allSatisfy(\.hasPermission)
    }

    /// Creates a new permissions manager. Tests pass their own permissions; nil uses the system's.
    init(accessibility: Permission? = nil, others: [Permission]? = nil, decisions: PermissionDecisions? = nil) {
        self.decisions = decisions
        self.accessibility = accessibility ?? AccessibilityPermission()
        self.others = others ?? FeaturePermissions.system + DataPermissions.system
        self.updatePermissionsState()
        // Permission is @Observable, so changes arrive via onChange.
        for permission in allPermissions {
            if permission.hasPermission {
                decisions?.recordGrant(for: permission.key)
            }
            permission.onChange = { [weak self] in
                guard let self else { return }
                if permission.hasPermission {
                    self.decisions?.recordGrant(for: permission.key)
                }
                updatePermissionsState()
                onPermissionTransition?(permission, permission.hasPermission)
            }
        }
    }

    /// Updates the current permissions state.
    private func updatePermissionsState() {
        permissionsState = allPermissions.filter(\.isRequired).allSatisfy(\.hasPermission) ? .hasAll : .missing
    }

    /// Refreshes permission grants from the system immediately.
    ///
    /// Also re-arms exhausted ungranted polls, since callers are surfaces the
    /// user is looking at.
    func refreshPermissionsState() {
        for permission in allPermissions {
            permission.resumePollingIfNeeded()
            permission.refreshStatus()
        }
        updatePermissionsState()
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}
