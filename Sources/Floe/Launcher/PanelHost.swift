//
//  PanelHost.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What the launcher model asks of the process around it: the panel, the HUD, settings and the resident.
/// Each process fills it where it is wired; the defaults keep a model usable without a window, as in tests.
struct PanelHost {
    var hidePanel: () -> Void = {}
    var showPanel: () -> Void = {}
    var showHUD: (String) -> Void = { _ in }
    /// Opens the settings window, on a page when one is named.
    var openSettings: (SettingsPage?) -> Void = { _ in }
    /// Pops the Actions menu of the search that is on screen: root, files or menu bar items.
    var showActions: () -> Void = {}
    /// Set only in the resident, which hands what the panel shows to the panel process.
    var presentInPanelProcess: ((PanelRequest) -> Void)?
    /// Set only in the panel process, which hands what the resident owns to the resident.
    var residentRequests: ((PanelPacket) -> Void)?
}
