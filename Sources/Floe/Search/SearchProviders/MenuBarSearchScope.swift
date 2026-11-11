//
//  MenuBarSearchScope.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `menu wifi`: the menu bar items that match. Reading them needs Accessibility; without it the
/// scope is one row that says so.
final class MenuBarSearchScope: SearchScope {
    /// Typing a query rescans at most this often; the scan is one Accessibility round trip per app.
    static let scanLifetime: TimeInterval = 10

    nonisolated static let word = "menu"

    let keyword = MenuBarSearchScope.word
    let title = String(localized: "Menu Bar Items", bundle: .floe)
    let emptyTitle = String(localized: "No menu bar items match", bundle: .floe)

    private let isTrusted: () -> Bool
    private let scan: @Sendable () -> [MenuBarExtra]
    private let now: () -> Date
    /// The last scan, shown at once while the next one runs.
    private var extras: [MenuBarExtra] = []
    private var scannedAt: Date?

    init(
        isTrusted: @escaping () -> Bool = { MenuBarExtras.isTrusted },
        scan: @escaping @Sendable () -> [MenuBarExtra] = MenuBarExtras.scan,
        now: @escaping () -> Date = Date.init
    ) {
        self.isTrusted = isTrusted
        self.scan = scan
        self.now = now
    }

    func results(for text: String, context: SearchContext) -> [RootItem] {
        guard isTrusted() else { return [.menuBarAccess] }
        return rows(for: text, names: context.menuBarItemNames)
    }

    func updates(for text: String, context: SearchContext) -> AsyncStream<[RootItem]>? {
        guard isTrusted() else { return nil }
        if let scannedAt, now().timeIntervalSince(scannedAt) < Self.scanLifetime {
            return nil
        }
        let scan = scan
        let names = context.menuBarItemNames
        let (stream, continuation) = AsyncStream<[RootItem]>.makeStream()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = scan()
            DispatchQueue.main.async { [weak self] in
                if let self {
                    extras = found
                    scannedAt = now()
                    continuation.yield(rows(for: text, names: names))
                }
                continuation.finish()
            }
        }
        return stream
    }

    private func rows(for text: String, names: [String: String]) -> [RootItem] {
        Self.ranked(extras, query: text, names: names).map { .menuBarItem($0, name: Self.displayName(for: $0, names: names)) }
    }

    /// The name the user gave the item, else the one its app reports.
    static func displayName(for extra: MenuBarExtra, names: [String: String]) -> String {
        names[extra.id].flatMap { $0.isEmpty ? nil : $0 } ?? extra.name
    }

    /// Items whose name or owning app matches, best first.
    static func ranked(_ extras: [MenuBarExtra], query: String, names: [String: String]) -> [MenuBarExtra] {
        extras.ranked { Ranking.menuBarScore(query: query, name: displayName(for: $0, names: names), owner: $0.ownerName) }
    }
}
