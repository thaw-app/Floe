//
//  Model+Mode.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Entering and leaving the modes, and what each one does as it goes.
extension LauncherModel {
    /// The mode on screen, unless a setup form or a command's view is drawn in front of it.
    var mode: LauncherMode? {
        modes.top
    }

    func enter(_ mode: LauncherMode) {
        if let replaced = modes.enter(mode) {
            end(replaced)
        }
    }

    func leave(_ kind: LauncherMode.Kind) {
        if let left = modes.leave(kind) {
            end(left)
        }
    }

    func leaveAllModes() {
        modes.leaveAll().forEach(end)
    }

    /// What a mode does as it goes, whether it was on screen or underneath.
    private func end(_ mode: LauncherMode) {
        switch mode {
        case .fileSearch: fileSearch.cancel()
        // The save is kept, for the next desk and the end of the process to wait on.
        case let .noteDesk(desk): noteDeskSave = desk.close()
        case let .askAI(asking): asking.leave()
        case .menuBarSearch, .menuItemSearch, .clipboardHistory: break
        }
    }

    var isSearchingFiles: Bool {
        if case .fileSearch = mode { true } else { false }
    }

    var menuItemSearch: MenuItemSearchModel? {
        if case let .menuItemSearch(search) = mode { search } else { nil }
    }

    var noteDesk: NoteDeskModel? {
        if case let .noteDesk(desk) = mode { desk } else { nil }
    }

    var askAI: AskAIModel? {
        if case let .askAI(asking) = mode { asking } else { nil }
    }
}
