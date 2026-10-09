//
//  Model+Focus.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Focus, as the launcher sets it: through the Shortcut the user named in Settings.
extension LauncherModel {
    /// Runs the Shortcut with what was asked as its input. With none named, opens Shortcuts and says what to do there.
    /// The task is for a test to wait on, and nil when nothing ran.
    @discardableResult
    func setFocus(_ request: FocusRequest, shortcut: String) -> Task<Void, Never>? {
        guard !shortcut.isEmpty else {
            reach(FocusRequest.shortcutsApp)
            showHUD(String(localized: "Make a Shortcut that sets your Focus, then name it in Settings › General", bundle: .floe, comment: "Shortcut is what Apple's Shortcuts app makes. Focus is the macOS feature that silences notifications."))
            return nil
        }
        hidePanel()
        reset()
        return shortcutLibrary.run(named: shortcut, input: request.input) { [weak self] in self?.showHUD($0) }
    }
}
