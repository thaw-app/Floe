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
        case .file, .clipboardEntry, .menuBarItem, .menuBarAccess, .browserTab, .webAddress, .shell, .process: true
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
        case let .app(app): app.origin ?? kind
        default: kind
        }
    }
}
