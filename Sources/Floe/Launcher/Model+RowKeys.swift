//
//  Model+RowKeys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

extension LauncherModel {
    /// Floe's keys on a result's rows, by its kind. With nothing selected, those of a result with no kind.
    func rowKeys(for item: RootItem?) -> ActionKeys {
        .floe(for: item.flatMap { SubjectKind.of($0) })
    }

    /// A key that means something only on the selected row: its owner's keys, then the keys of the rows of its
    /// Actions menu, then Tab, which completes a shell suggestion or lists an application's recently used files,
    /// and Space, which shows a file in Quick Look once the arrows have moved to it. False for any other key.
    func handleRowKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        let item = selectedRootItem
        if let item, ownerHandlesKey(event.keyCode, flags: flags, on: item) {
            return true
        }
        let collapsed = panelState.isCollapsed(in: settings.launcherLayout)
        if ActionKeys.handle(ActionKeys.pressed(event.keyCode, flags), keys: { rowKeys(for: item) }, rows: { item.map { rootActions(for: $0) } ?? [] }, collapsed: collapsed) {
            return true
        }
        switch (event.keyCode, item) {
        case let (48, .app(app)?) where flags.isEmpty:
            query = RecentDocuments.keyword + " " + app.name
            focusToken += 1
        case let (49, .file(file)?) where flags.isEmpty && typing.isBrowsing:
            QuickLookPresenter.shared.show(file.url)
        default:
            return false
        }
        return true
    }
}
