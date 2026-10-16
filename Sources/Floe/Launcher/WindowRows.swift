//
//  WindowRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Open windows the search found: Return brings one forward, and its menu minimizes or closes it.
final class WindowRows {
    var host = RowHost()

    static func title(for row: WindowRow) -> String {
        switch row {
        case .window: String(localized: "Switch to Window", bundle: .floe)
        case .access: String(localized: "Open Privacy Settings", bundle: .floe, comment: "A button that opens the Privacy pane of System Settings.")
        }
    }

    /// Return on a window: the launcher goes first, so the window comes forward over nothing of Floe's.
    func open(_ row: WindowRow) {
        switch row {
        case let .window(window):
            host.leave()
            OpenWindows.focus(window)
        case .access:
            MenuBarExtras.requestAccess()
        }
    }

    func windowActions(for window: OpenWindow) -> [ItemAction?] {
        var actions: [ItemAction?] = [nil]
        if !window.isMinimized {
            actions.append(ItemAction(title: String(localized: "Minimize Window", bundle: .floe), symbol: "minus.rectangle") { [weak self] in
                OpenWindows.minimize(window)
                self?.host.rescan()
            })
        }
        actions.append(ItemAction(title: String(localized: "Close Window", bundle: .floe), symbol: "xmark.rectangle") { [weak self] in
            OpenWindows.close(window)
            self?.host.rescan()
        })
        return actions
    }
}

extension WindowRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case let .window(row) = item else { return nil }
        return Self.title(for: row)
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .window(row) = item else { return false }
        open(row)
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .window(.window(window)) = item else { return nil }
        return windowActions(for: window)
    }
}
