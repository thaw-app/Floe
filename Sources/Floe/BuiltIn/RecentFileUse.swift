//
//  RecentFileUse.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Synchronization

/// When files were last opened, as Spotlight knows it. The index holds names only, so this is what lets a
/// file opened today lead one untouched for years.
final class RecentFileUse {
    static let shared = RecentFileUse()

    /// A file opened longer ago than this counts as not opened.
    static nonisolated let window: TimeInterval = 30 * 24 * 3600
    /// How long one answer from Spotlight is used before it is asked again.
    static nonisolated let lifetime: TimeInterval = 300

    /// Read at each key from the search's own thread, so it is kept apart from the query that fills it.
    private static nonisolated let dates = Mutex<[String: Date]>([:])

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var taken = Date.distantPast

    static nonisolated func date(for path: String) -> Date? {
        dates.withLock { $0[path] }
    }

    /// Asks Spotlight again when the last answer is old. It answers later; until then the earlier dates are used.
    func refreshIfStale(now: Date = Date()) {
        guard query == nil, now.timeIntervalSince(taken) >= Self.lifetime else { return }
        taken = now
        let metadata = NSMetadataQuery()
        metadata.searchScopes = [NSMetadataQueryUserHomeScope]
        metadata.predicate = NSPredicate(format: "%K >= %@", "kMDItemLastUsedDate", now.addingTimeInterval(-Self.window) as NSDate)
        observer = NotificationCenter.default.addMainObserver(forName: .NSMetadataQueryDidFinishGathering, object: metadata) { [weak self] in
            self?.finish()
        }
        query = metadata
        metadata.start()
    }

    /// The dates are kept only while the index that uses them is.
    func follow(_ isOn: Bool) {
        if isOn {
            refreshIfStale()
        } else {
            forget()
        }
    }

    func forget() {
        stop()
        taken = .distantPast
        Self.dates.withLock { $0 = [:] }
    }

    private func finish() {
        guard let metadata = query else { return }
        metadata.disableUpdates()
        var found: [String: Date] = [:]
        for case let item as NSMetadataItem in metadata.results {
            if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String, let date = item.value(forAttribute: "kMDItemLastUsedDate") as? Date {
                found[path] = date
            }
        }
        Self.dates.withLock { $0 = found }
        stop()
    }

    private func stop() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        query?.stop()
        query = nil
    }
}
