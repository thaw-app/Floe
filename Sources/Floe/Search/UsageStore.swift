//
//  UsageStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// How often and how recently each root item was opened, for ranking. Kept apart from settings
/// because it changes on every launch.
final class UsageStore {
    static let shared = UsageStore()

    struct Record: Codable {
        var count: Int
        var lastUsed: Date
    }

    private(set) var records: [String: Record]
    /// The searches that ended in something being opened, oldest first, each once. Read from the defaults
    /// each time: the settings window is another process, and clears them there.
    var queries: [String] {
        defaults.stringArray(forKey: Self.queriesKey) ?? []
    }

    static let queryLimit = 50
    private static let defaultsKey = "usage"
    private static let queriesKey = "queries"
    /// How long a burst of uses is gathered before the map is written once.
    static let saveDelay: TimeInterval = 1
    private let defaults: UserDefaults
    private let now: () -> Date
    /// Runs a deferred save. `later` is injectable so a test can run the timer by hand.
    private let later: (TimeInterval, DispatchWorkItem) -> Void
    /// The save waiting for its timer. Nil once it has run or been flushed.
    private var pendingSave: DispatchWorkItem?

    /// `now` is injectable so ranking by recency can be tested against a fixed clock.
    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        later: @escaping (TimeInterval, DispatchWorkItem) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) }
    ) {
        self.defaults = defaults
        self.now = now
        self.later = later
        records = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    /// Remembers a search for the Up arrow to bring back. One typed again moves to the newest place.
    func recordQuery(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var queries = queries
        queries.removeAll { $0 == query }
        queries.append(query)
        queries.removeFirst(max(0, queries.count - Self.queryLimit))
        defaults.set(queries, forKey: Self.queriesKey)
    }

    func forgetQueries() {
        defaults.removeObject(forKey: Self.queriesKey)
    }

    /// Counts the use at once and writes it down later, in one save per burst: recording what was
    /// opened no longer encodes the whole map and carries it through the defaults server at the
    /// very moment the panel is giving way to an app. A burst restarts the timer, so uses keep joining it.
    func recordUse(of id: String) {
        var record = records[id] ?? Record(count: 0, lastUsed: .distantPast)
        record.count += 1
        record.lastUsed = now()
        records[id] = record
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        later(Self.saveDelay, work)
    }

    /// Writes what has not been saved yet: when the burst's timer runs out, and when the app quits.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func frecency(of id: String) -> Double {
        guard let record = records[id] else { return 0 }
        return Ranking.frecency(count: record.count, age: now().timeIntervalSince(record.lastUsed))
    }
}
