//
//  ScopeRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What sets the rows of a scope or a source apart from the rest of the root search.
extension RootItem {
    /// A scope's row stands for one thing found just now: it has no place among favorites or in the usage record.
    var isScopeResult: Bool {
        switch self {
        case let .focus(request, _): request != .toggle
        case .file, .clipboardEntry, .menuBarItem, .menuBarAccess, .browserTab, .webAddress, .shell, .process, .receipt, .checkpointDraft, .reminderDraft, .eventDraft, .timer, .contact, .outgoing, .keyword: true
        default: false
        }
    }

    /// The text at the row's right edge: the kind, or for a scope's row what tells it from its neighbours.
    var rowLabel: String {
        switch self {
        case let .file(file): file.url.deletingLastPathComponent().lastPathComponent
        case let .clipboardEntry(entry): entry.sourceApp ?? entry.kind.rawValue.capitalized
        case let .menuBarItem(extra, name): extra.ownerName.isEmpty || extra.ownerName == name ? kind : extra.ownerName
        case let .browserTab(row): row.label
        case let .process(process): Processes.label(for: process)
        case let .receipt(receipt): receipt.label()
        case let .checkpoint(checkpoint): checkpoint.summary
        case let .reminderDraft(draft): draft.label()
        case let .eventDraft(draft): draft.label()
        case let .timer(row): row.label ?? kind
        case let .contact(.person(person)): person.detail ?? kind
        case let .outgoing(draft): draft.label ?? kind
        case let .focus(_, shortcut): FocusRequest.label(shortcut: shortcut)
        case let .keyword(hint): hint.detail
        case let .app(app): app.origin ?? kind
        default: kind
        }
    }
}
