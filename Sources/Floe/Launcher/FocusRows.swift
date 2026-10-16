//
//  FocusRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Focus, as the launcher sets it: through the Shortcut the user named in Settings.
final class FocusRows {
    var host = RowHost()
    /// Runs the Shortcut by its name with text as its input, saying what came of it. The task is for a test to wait on.
    var runShortcut: (_ name: String, _ input: String, _ say: @escaping (String) -> Void) -> Task<Void, Never>? = { _, _, _ in nil }

    /// Runs the Shortcut with what was asked as its input. With none named, opens Shortcuts and says what to do there.
    /// The task is for a test to wait on, and nil when nothing ran.
    @discardableResult
    func setFocus(_ request: FocusRequest, shortcut: String) -> Task<Void, Never>? {
        guard !shortcut.isEmpty else {
            host.reach(FocusRequest.shortcutsApp)
            host.showHUD(String(localized: "Make a Shortcut that sets your Focus, then name it in Settings › General", bundle: .floe, comment: "Shortcut is what Apple's Shortcuts app makes. Focus is the macOS feature that silences notifications."))
            return nil
        }
        host.leave()
        return runShortcut(shortcut, request.input) { [weak self] in self?.host.showHUD($0) }
    }
}

extension FocusRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        switch item {
        case let .focus(_, shortcut) where shortcut.isEmpty: String(localized: "Open Shortcuts", bundle: .floe, comment: "A button that opens Apple's Shortcuts app.")
        case .focus: String(localized: "Run Shortcut", bundle: .floe, comment: "A button that runs the Shortcut the user named for Focus.")
        default: nil
        }
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .focus(request, shortcut) = item else { return false }
        setFocus(request, shortcut: shortcut)
        return true
    }
}
