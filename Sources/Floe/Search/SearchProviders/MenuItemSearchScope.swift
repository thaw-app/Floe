//
//  MenuItemSearchScope.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `menus export`: the commands in the front app's menus that match. The word alone lists them all.
/// Reading them needs Accessibility; without it the scope is one row that says so.
final class MenuItemSearchScope: SearchScope {
    /// Typing a query reads the menus again at most this often, unless another app came to the front.
    static let scanLifetime: TimeInterval = 10

    let keyword = MenuItems.keyword
    let title = String(localized: "Menu Items", bundle: .floe)
    let emptyTitle = String(localized: "No menu items match", bundle: .floe)

    private let isTrusted: () -> Bool
    private let frontApp: () -> MenuTarget?
    private let scan: @Sendable (pid_t) -> [AppMenuItem]
    private let now: () -> Date
    /// The last read, and whose menus it read, shown at once while the next one runs.
    private var entries: [AppMenuItem] = []
    private var scanned: (target: MenuTarget, at: Date)?

    init(
        isTrusted: @escaping () -> Bool = { MenuBarExtras.isTrusted },
        frontApp: @escaping () -> MenuTarget? = { MenuItems.frontApp() },
        scan: @escaping @Sendable (pid_t) -> [AppMenuItem] = MenuSearchScanner.entries,
        now: @escaping () -> Date = Date.init
    ) {
        self.isTrusted = isTrusted
        self.frontApp = frontApp
        self.scan = scan
        self.now = now
    }

    func text(in context: SearchContext) -> String? {
        context.text(afterOrAlone: keyword)
    }

    func results(for text: String, context _: SearchContext) -> [RootItem] {
        guard isTrusted() else { return [.menuItem(.access)] }
        guard let target = frontApp(), scanned?.target == target else { return [] }
        return Self.rows(entries, query: text, target: target)
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        guard isTrusted(), let target = frontApp() else { return nil }
        if let scanned, scanned.target == target, now().timeIntervalSince(scanned.at) < Self.scanLifetime {
            return nil
        }
        let scan = scan
        let (stream, continuation) = AsyncStream<[RootItem]>.makeStream()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = scan(target.pid)
            DispatchQueue.main.async { [weak self] in
                if let self {
                    entries = found
                    scanned = (target, now())
                    continuation.yield(Self.rows(found, query: text, target: target))
                }
                continuation.finish()
            }
        }
        return stream
    }

    nonisolated static func rows(_ entries: [AppMenuItem], query: String, target: MenuTarget) -> [RootItem] {
        MenuItems.ranked(entries, query: query).map { .menuItem(.item($0, in: target)) }
    }
}
