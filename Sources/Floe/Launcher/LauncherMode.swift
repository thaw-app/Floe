//
//  LauncherMode.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A view the launcher shows instead of the root search.
enum LauncherMode {
    case menuBarSearch
    case menuItemSearch(MenuItemSearchModel)
    case clipboardHistory
    case fileSearch
    case noteDesk(NoteDeskModel)
    case askAI(AskAIModel)

    enum Kind {
        case menuBarSearch, menuItemSearch, clipboardHistory, fileSearch, noteDesk, askAI
    }

    var kind: Kind {
        switch self {
        case .menuBarSearch: .menuBarSearch
        case .menuItemSearch: .menuItemSearch
        case .clipboardHistory: .clipboardHistory
        case .fileSearch: .fileSearch
        case .noteDesk: .noteDesk
        case .askAI: .askAI
        }
    }

    /// The model a mode made for this showing only; the others keep one model for every showing.
    private var ownModel: AnyObject? {
        switch self {
        case let .menuItemSearch(search): search
        case let .noteDesk(desk): desk
        case let .askAI(asking): asking
        case .menuBarSearch, .clipboardHistory, .fileSearch: nil
        }
    }

    /// The same mode with the same model, so entering it again is not a new showing.
    func isSame(as other: LauncherMode) -> Bool {
        kind == other.kind && ownModel === other.ownModel
    }
}

/// The modes open in the launcher, the one on screen last. Each kind is open once: entering one already open brings it
/// to the top.
struct ModeStack {
    private(set) var modes: [LauncherMode] = []

    var top: LauncherMode? {
        modes.last
    }

    func contains(_ kind: LauncherMode.Kind) -> Bool {
        modes.contains { $0.kind == kind }
    }

    /// Whether this Ask AI conversation is still open, on screen or under another mode.
    func holds(_ asking: AskAIModel) -> Bool {
        modes.contains { if case let .askAI(open) = $0 { open === asking } else { false } }
    }

    /// Puts the mode on top and answers the earlier showing of its kind for the caller to end, if there was another.
    mutating func enter(_ mode: LauncherMode) -> LauncherMode? {
        let earlier = leave(mode.kind)
        modes.append(mode)
        guard let earlier, !earlier.isSame(as: mode) else { return nil }
        return earlier
    }

    /// Takes the mode of this kind out, wherever it is, and answers it for the caller to end.
    mutating func leave(_ kind: LauncherMode.Kind) -> LauncherMode? {
        guard let index = modes.firstIndex(where: { $0.kind == kind }) else { return nil }
        return modes.remove(at: index)
    }

    /// Takes every mode out, the one on screen first, and answers them for the caller to end.
    mutating func leaveAll() -> [LauncherMode] {
        let open: [LauncherMode] = modes.reversed()
        modes = []
        return open
    }
}
