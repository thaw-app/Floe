//
//  PanelHost.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What the launcher model asks of the app around it: the panel, the HUD and settings. The app fills it where it is
/// wired; the defaults keep a model usable without a window, as in tests.
struct PanelHost {
    var hidePanel: () -> Void = { /* no panel */ }
    var showPanel: () -> Void = { /* no panel */ }
    var showHUD: (String) -> Void = { _ in
        // No HUD.
    }
    /// Opens the settings window, on a page when one is named.
    var openSettings: (SettingsPage?) -> Void = { _ in
        // No settings window.
    }
    /// Pops the Actions menu of the search that is on screen: root, files or menu bar items.
    var showActions: () -> Void = { /* no panel */ }
    /// Opens the floating note's window, or brings it forward. Set only where the panel is drawn.
    var showFloatingNote: () -> Void = { /* no window */ }
}
