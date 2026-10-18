//
//  Model+Showing.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension LauncherModel {
    /// Reads again what may have changed while the panel was away: scripts, hosts, shortcuts, permissions and
    /// stale search data. Called once the panel is on screen, so none of it holds the shortcut up.
    func panelDidShow() {
        pointerRest.rest()
        catalog.reloadScripts(quietly: true)
        catalog.reloadSSHHosts()
        features.shortcuts.reload()
        // A grant made in System Settings with no request from Floe is noticed here.
        menuBarSearch.warm()
        ExchangeRateUpdater.shared.refreshIfStale()
        features.checkpoints.reload()
        if FileIndexService.shared.state != .off {
            RecentFileUse.shared.refreshIfStale()
        }
    }
}
