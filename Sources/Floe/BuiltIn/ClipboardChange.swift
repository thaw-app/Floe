//
//  ClipboardChange.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What the panel's copy of the history needs after the resident saved: the entries that are new or
/// changed and the ones gone, or the whole list read again from disk.
nonisolated enum ClipboardChange: Codable, Sendable, Equatable {
    case reload
    case entries(changed: [ClipboardEntry], removed: [UUID])

    /// Nil when the two lists hold the same entries.
    static func between(_ old: [ClipboardEntry], _ new: [ClipboardEntry]) -> ClipboardChange? {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(new.map(\.id))
        let changed = new.filter { before[$0.id] != $0 }
        let removed = old.map(\.id).filter { !kept.contains($0) }
        return changed.isEmpty && removed.isEmpty ? nil : .entries(changed: changed, removed: removed)
    }
}
