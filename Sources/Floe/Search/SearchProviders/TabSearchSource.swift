//
//  TabSearchSource.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `tabs invoice`: the open tabs of the running browsers that match, by title and address.
/// Only the main thread touches it; a read hops back there before it answers.
final class TabSearchSource: SearchSource {
    /// Typing a query asks the browsers again at most this often.
    static let listLifetime: TimeInterval = 5

    let id = SearchSourceInfo.tabs.id
    nonisolated static let word = "tabs"

    let keyword = TabSearchSource.word
    let title = String(localized: "Browser Tabs", bundle: .floe)
    let emptyTitle = String(localized: "No open tabs match", bundle: .floe)

    private let browsers: [BrowserApp]
    private let isRunning: (BrowserApp) -> Bool
    private let run: AppleScriptRunner
    private let now: () -> Date
    /// The last answer, shown at once while the next one is on its way.
    private var snapshot = BrowserTabs.Snapshot()
    private var readAt: Date?
    /// Everyone waiting for the read in flight; one read answers them all.
    private var waiting: [(BrowserTabs.Snapshot) -> Void] = []

    init(
        browsers: [BrowserApp] = BrowserApp.all,
        isRunning: @escaping (BrowserApp) -> Bool = BrowserApp.isRunning,
        run: @escaping AppleScriptRunner = AppleScript.run,
        now: @escaping () -> Date = Date.init
    ) {
        self.browsers = browsers
        self.isRunning = isRunning
        self.run = run
        self.now = now
    }

    func results(for text: String, context _: SearchContext) -> [RootItem] {
        Self.rows(snapshot, query: text, withAccess: true)
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        later(text, withAccess: true)
    }

    /// An ordinary search shows tabs only: a browser that refused adds nothing while someone types.
    func inlineResults(for text: String, context _: SearchContext) -> [RootItem] {
        Self.rows(snapshot, query: text, withAccess: false)
    }

    func inlineUpdates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        later(text, withAccess: false)
    }

    /// The matching tabs, then one row per browser that has to be allowed first.
    static func rows(_ snapshot: BrowserTabs.Snapshot, query: String, withAccess: Bool) -> [RootItem] {
        BrowserTabs.matching(snapshot.tabs, query: query).map { .browserTab(.tab($0)) }
            + (withAccess ? snapshot.refused.map { .browserTab(.access($0)) } : [])
    }

    private func later(_ text: String, withAccess: Bool) -> AsyncStream<[RootItem]>? {
        if let readAt, now().timeIntervalSince(readAt) < Self.listLifetime {
            return nil
        }
        return AsyncStream { continuation in
            read { snapshot in
                continuation.yield(Self.rows(snapshot, query: text, withAccess: withAccess))
                continuation.finish()
            }
        }
    }

    /// Asks the running browsers for their tabs. A browser that is not running is not asked.
    private func read(_ completion: @escaping (BrowserTabs.Snapshot) -> Void) {
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        let running = browsers.filter(isRunning)
        Task(priority: .userInitiated) { [weak self, run] in
            let found = await BrowserTabs.read(running, run: run)
            self?.finish(found)
        }
    }

    private func finish(_ found: BrowserTabs.Snapshot) {
        snapshot = found
        readAt = now()
        let answered = waiting
        waiting = []
        answered.forEach { $0(found) }
    }
}
