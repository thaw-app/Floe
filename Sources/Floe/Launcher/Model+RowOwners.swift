//
//  Model+RowOwners.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

extension LauncherModel {
    func ownerReturnTitle(for item: RootItem) -> String? {
        features.rowOwners.lazy.compactMap { $0.returnTitle(for: item) }.first
    }

    func openByOwner(_ item: RootItem, flags: NSEvent.ModifierFlags = []) -> Bool {
        features.rowOwners.contains { $0.open(item, flags: flags) }
    }

    func ownerActions(for item: RootItem) -> [ItemAction?]? {
        features.rowOwners.lazy.compactMap { $0.actions(for: item) }.first
    }

    func ownerHandlesKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, on item: RootItem) -> Bool {
        features.rowOwners.contains { $0.handleKey(keyCode, flags: flags, on: item) }
    }

    /// Hides the panel and goes back to the root search.
    func leave() {
        panelHost.hidePanel()
        reset()
    }

    /// Opens a link through the system once the panel is gone. A link that could not be made opens nothing.
    func reach(_ link: URL?) {
        leave()
        if let link {
            linkOpener.open(link, nil)
        }
    }

    /// Keeps a receipt of something Floe did, unless the user switched that off.
    func record(_ receipt: Receipt) {
        features.receipts.record(receipt)
    }
}
