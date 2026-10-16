//
//  ShortcutRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// The user's shortcuts from Apple's Shortcuts app, as the launcher lists, runs and opens them.
final class ShortcutRows {
    var host = RowHost()
    /// The switch in Settings, Privacy. Off, the Shortcuts tool is never started.
    var isOn: () -> Bool = { false }
    /// The list was read again.
    var listChanged: () -> Void = {}
    /// The shortcuts and their runs. Nothing is read while the switch is off.
    lazy var library = AppleShortcutLibrary()

    /// What the search may show: nothing the moment the switch goes off.
    var forSearch: [AppleShortcut] {
        isOn() ? library.shortcuts : []
    }

    /// Asks for the list again. The task is nil when the switch is off, and is for tests to wait on.
    @discardableResult
    func reload() -> Task<Void, Never>? {
        library.refresh(isOn: isOn()) { [weak self] in self?.listChanged() }
    }

    /// Return on a shortcut: the panel goes, the run goes on behind it, and only a failure is heard of.
    func run(_ shortcut: AppleShortcut) {
        host.leave()
        _ = library.run(shortcut, showHUD: host.showHUD)
    }

    func openInShortcuts(_ shortcut: AppleShortcut) {
        host.leave()
        _ = library.openInShortcuts(shortcut, showHUD: host.showHUD)
    }
}

extension ShortcutRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case .shortcut = item else { return nil }
        return String(localized: "Run", bundle: .floe, comment: "A verb on a button: run the shortcut or script.")
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .shortcut(shortcut) = item else { return false }
        run(shortcut)
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .shortcut(shortcut) = item else { return nil }
        return [
            nil,
            ItemAction(title: String(localized: "Open in Shortcuts", bundle: .floe, comment: "Shortcuts is the name of Apple's app."), symbol: "arrow.up.forward.app") { [weak self] in self?.openInShortcuts(shortcut) },
            ItemAction(title: String(localized: "Copy Name", bundle: .floe), symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(shortcut.name)
                self?.host.showHUD(String(localized: "Copied \(shortcut.name)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            },
        ]
    }
}

/// The Shortcuts app's icon says where a shortcut runs; a plain tile stands in on a Mac without the app.
struct AppleShortcutIcon: View {
    static let applicationPath = "/System/Applications/Shortcuts.app"
    private static let hasApplication = FileManager.default.fileExists(atPath: applicationPath)

    var body: some View {
        if Self.hasApplication {
            AppIconView(path: Self.applicationPath, size: 24)
        } else {
            SymbolTile(symbol: "square.2.layers.3d")
        }
    }
}
