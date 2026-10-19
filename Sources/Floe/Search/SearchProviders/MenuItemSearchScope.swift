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
    /// Hands a finished read to the main thread; a test wraps it to know when a read was taken or dropped.
    private let onMain: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
    /// The last read, and whose menus it read, shown at once while the next one runs.
    private var entries: [AppMenuItem] = []
    private var scanned: (target: MenuTarget, at: Date)?
    /// The read in flight and the newest search waiting on it: typing while it runs starts no second walk.
    /// Numbered, so an older read of the same app that ends late is not taken for it.
    private var pending: (read: Int, target: MenuTarget, query: String, continuation: AsyncStream<[RootItem]>.Continuation)?
    private var reads = 0

    init(
        isTrusted: @escaping () -> Bool = { MenuBarExtras.isTrusted },
        frontApp: @escaping () -> MenuTarget? = { MenuItems.frontApp() },
        scan: @escaping @Sendable (pid_t) -> [AppMenuItem] = MenuSearchScanner.entries,
        now: @escaping () -> Date = Date.init,
        onMain: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
    ) {
        self.isTrusted = isTrusted
        self.frontApp = frontApp
        self.scan = scan
        self.now = now
        self.onMain = onMain
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
        let (stream, continuation) = AsyncStream<[RootItem]>.makeStream()
        let joined = pending.flatMap { $0.target == target ? $0.read : nil }
        pending?.continuation.finish()
        let read = joined ?? reads + 1
        reads = read
        pending = (read, target, text, continuation)
        if joined == nil {
            self.read(target, number: read)
        }
        return stream
    }

    private func read(_ target: MenuTarget, number: Int) {
        let scan = scan
        let onMain = onMain
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = scan(target.pid)
            onMain { [weak self] in
                guard let self, let pending, pending.read == number else { return }
                // Another app came to the front while this one's menus were read: they are not its commands.
                guard frontApp() == target else {
                    pending.continuation.finish()
                    self.pending = nil
                    return
                }
                entries = found
                scanned = (target, now())
                pending.continuation.yield(Self.rows(found, query: pending.query, target: target))
                pending.continuation.finish()
                self.pending = nil
            }
        }
    }

    nonisolated static func rows(_ entries: [AppMenuItem], query: String, target: MenuTarget) -> [RootItem] {
        MenuItems.ranked(entries, query: query).map { .menuItem(.item($0, in: target)) }
    }
}
