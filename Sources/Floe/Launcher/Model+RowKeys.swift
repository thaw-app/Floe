//
//  Model+RowKeys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

extension LauncherModel {
    /// A key that means something only on the kind of row that is selected: Tab completes a shell suggestion
    /// or lists an application's recently used files, and Command-Y shows a file in Quick Look, as Space does
    /// once the arrows have moved to it. False for any other key or row.
    func handleRowKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard results.indices.contains(selection) else { return false }
        let item = results[selection].item
        if ownerHandlesKey(event.keyCode, flags: flags, on: item) {
            return true
        }
        switch (event.keyCode, item) {
        case let (48, .app(app)) where flags.isEmpty:
            query = RecentDocuments.keyword + " " + app.name
            focusToken += 1
        case let (16, .file(file)) where flags == .command,
             let (49, .file(file)) where flags.isEmpty && typing.isBrowsing:
            QuickLookPresenter.shared.show(file.url)
        default:
            return false
        }
        return true
    }
}
