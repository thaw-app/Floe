//
//  CatalogLoader.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Where a model gets its catalog: the real scanners in a worker, or a controlled fake in tests.
nonisolated protocol CatalogScanning: Sendable {
    func scanApps() async -> [AppEntry]
    func scanCommands(includeRaycast: Bool) async -> [ExtensionCommand]
    func scanScripts() async -> ScriptScan
    func scanSettingsPanes() async -> [SystemSettingsPane]
    func scanSSHHosts() async -> [SSHHost]
}

nonisolated extension CatalogScanning {
    func scanScripts() async -> ScriptScan {
        ScriptScan()
    }

    func scanSettingsPanes() async -> [SystemSettingsPane] {
        []
    }

    func scanSSHHosts() async -> [SSHHost] {
        []
    }
}

/// An immutable catalog handed to a model that must be usable without waiting for a scan.
nonisolated struct CatalogSnapshot: Sendable {
    let apps: [AppEntry]
    let commands: [ExtensionCommand]
    var scripts: [ScriptCommand] = []
    var scriptFailures: [ScriptFailure] = []
    var settingsPanes: [SystemSettingsPane] = []
    var sshHosts: [SSHHost] = []
}

/// Runs the existing synchronous scanners away from the main actor. The actor only serializes the
/// scans; ordering, filtering and error behavior stay with the scanners themselves, and support-folder
/// preparation can never interleave with a command scan.
actor CatalogLoader: CatalogScanning {
    /// Not queued with the other scans: reading the apps' other names from Spotlight takes a moment, and an app scan
    /// touches nothing the other scans share, so the commands needn't wait for it.
    @concurrent nonisolated func scanApps() async -> [AppEntry] {
        AppEntry.scan()
    }

    func scanCommands(includeRaycast: Bool) async -> [ExtensionCommand] {
        ExtensionCommand.scan(includeRaycast: includeRaycast)
    }

    func scanScripts() async -> ScriptScan {
        ScriptCommand.scan()
    }

    func scanSettingsPanes() async -> [SystemSettingsPane] {
        SystemSettingsPane.scan()
    }

    func scanSSHHosts() async -> [SSHHost] {
        SSHConfig.hosts(files: .user)
    }
}
