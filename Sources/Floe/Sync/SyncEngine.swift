//
//  SyncEngine.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What sync is doing, for the app to show.
nonisolated struct SyncStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case off
        /// This build carries no entitlement for iCloud, so the store is never touched.
        case notSigned
        case noAccount
        case syncing
        case synced(Date)
        /// The records would pass the store's limits, so nothing more is written.
        case full
    }

    var state = State.off
    /// Values in the store, or records the app refused, that were left alone because they could not be read.
    var skipped = 0

    /// The status as one string, for a process that shows it without holding the engine.
    var text: String {
        let name = switch state {
        case .off: "off"
        case .notSigned: "notSigned"
        case .noAccount: "noAccount"
        case .syncing: "syncing"
        case let .synced(date): "synced@\(date.timeIntervalSince1970)"
        case .full: "full"
        }
        return "\(name);\(skipped)"
    }

    init(state: State = .off, skipped: Int = 0) {
        self.state = state
        self.skipped = skipped
    }

    init?(text: String) {
        let parts = text.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count == 2, let skipped = Int(parts[1]), skipped >= 0 else { return nil }
        let name = parts[0]
        switch name {
        case "off": state = .off
        case "notSigned": state = .notSigned
        case "noAccount": state = .noAccount
        case "syncing": state = .syncing
        case "full": state = .full
        default:
            guard name.hasPrefix("synced@"), let time = Double(name.dropFirst(7)), time.isFinite else { return nil }
            state = .synced(Date(timeIntervalSince1970: time))
        }
        self.skipped = skipped
    }
}

/// What the engine remembers between launches.
nonisolated struct SyncJournal: Codable, Equatable {
    /// This Mac's name in the records it writes. Made once.
    var device: String
    /// The newest record known for each key, removals among them.
    var records: [String: SyncRecord] = [:]
    /// A digest of what the app held under each key at the last look. A key missing here was missing there.
    var seen: [String: String] = [:]
    /// Whether sync was on at the last look, to tell switching it on from finding it on at launch.
    var wasOn = false
    /// The time of the newest "everything was removed from iCloud" note this Mac has acted on.
    var clearedAt: TimeInterval = 0
}

/// Where the journal is kept.
struct SyncJournalStorage {
    var load: () -> SyncJournal?
    var save: (SyncJournal) -> Void

    static func file(_ url: URL) -> SyncJournalStorage {
        SyncJournalStorage(
            load: { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SyncJournal.self, from: $0) } },
            save: { journal in
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(journal).write(to: url, options: .atomic)
            }
        )
    }
}

/// The app's side of sync: what it holds, and how it takes what another Mac changed.
struct SyncClient {
    /// Every value that syncs, as JSON text by key. The same content must give the same text each time.
    var snapshot: () -> [String: String]
    /// What a fresh install holds. A value still at its default counts as never changed, so it loses to any change.
    var defaults: [String: String] = [:]
    /// Takes in the values another Mac changed and removed. Answers with the keys it refused.
    var apply: (_ changed: [String: String], _ removed: Set<String>) -> Set<String>
    /// Switches sync off in the app, when another Mac removed the settings from iCloud.
    var turnOff: () -> Void = { /* an app without a switch has nothing to turn */ }
}

/// Keeps the app's values and a key-value store in step, one record per key, newest change winning.
/// It notes when each value changed even while sync is off, so switching it on later can merge by age.
final class SyncEngine {
    /// The key of the note that everything was removed from the store. No record uses a key that starts like this.
    static let clearedKey = "~cleared"

    private let client: SyncClient
    private let storage: SyncJournalStorage
    private let availability: SyncAvailability
    private let makeStore: () -> any SyncStore
    private let now: () -> Date
    private var store: (any SyncStore)?
    private(set) var journal: SyncJournal
    private(set) var isOn = false
    private var isFull = false
    /// A deliberate join accepts the clear marker in the first download, not a later removal.
    private var acceptsInitialClear = false
    private(set) var status = SyncStatus() {
        didSet {
            if status != oldValue {
                onStatusChange?(status)
            }
        }
    }

    var onStatusChange: ((SyncStatus) -> Void)?

    /// `makeStore` runs once, and only after `availability` said the build is entitled.
    init(
        client: SyncClient,
        storage: SyncJournalStorage,
        availability: SyncAvailability = .system,
        makeStore: @escaping () -> any SyncStore = { UbiquitousSyncStore() },
        now: @escaping () -> Date = Date.init,
        device: () -> String = { UUID().uuidString }
    ) {
        self.client = client
        self.storage = storage
        self.availability = availability
        self.makeStore = makeStore
        self.now = now
        journal = storage.load() ?? SyncJournal(device: device())
        status.state = availability.isEntitled() ? .off : .notSigned
    }

    /// Follows the app's switch. Off stops the exchange and leaves the app's values and the store's as they are.
    func setOn(_ isOn: Bool) {
        self.isOn = isOn
        if isOn, !journal.wasOn {
            acceptsInitialClear = true
            if let store = openStore() {
                journal.clearedAt = max(journal.clearedAt, Self.clearedTime(in: store.all()))
            }
        }
        if journal.wasOn != isOn {
            journal.wasOn = isOn
            storage.save(journal)
        }
        refresh()
    }

    /// Call when the app's values may have changed. Notes what did, and sends it when sync is on.
    func localChanged() {
        if isActive {
            refresh()
        } else if track() {
            storage.save(journal)
        }
    }

    /// Reads the store, takes in what is newer there, and sends what is newer here.
    func refresh() {
        let before = journal
        let changedHere = track()
        // The store is opened without an account too: it is what says when one signs in.
        guard isOn, let store = openStore(), availability.hasAccount() else {
            status = SyncStatus(state: idleState)
            if changedHere {
                storage.save(journal)
            }
            return
        }
        status.state = .syncing
        let contents = store.all()
        if Self.clearedTime(in: contents) > journal.clearedAt {
            journal.clearedAt = Self.clearedTime(in: contents)
            stop()
            return
        }
        var (remote, skipped) = SyncWire.decode(contents.filter { $0.key != Self.clearedKey })
        var outcome = SyncMerge.merge(local: journal.records, remote: remote)
        skipped += take(&outcome, from: remote)
        send(outcome.push, to: store, holding: &remote)
        forgetOldRemovals(in: store, holding: remote)
        if journal != before {
            storage.save(journal)
        }
        status = SyncStatus(state: isFull ? .full : .synced(now()), skipped: skipped)
    }

    /// Deletes every record from the store and leaves a note there, so each Mac that syncs switches itself off.
    func removeFromCloud() {
        guard availability.isEntitled(), availability.hasAccount(), let store = openStore() else { return }
        for key in store.all().keys {
            store.remove(key)
        }
        let note = SyncRecord(value: nil, time: stamp(after: journal.clearedAt), device: journal.device)
        store.set(SyncWire.encode(note, key: Self.clearedKey), for: Self.clearedKey)
        store.synchronize()
        journal.clearedAt = note.time
        isFull = false
        stop()
    }

    private var isActive: Bool {
        isOn && availability.isEntitled() && availability.hasAccount()
    }

    private var idleState: SyncStatus.State {
        if !availability.isEntitled() {
            return .notSigned
        }
        return isOn ? .noAccount : .off
    }

    private func stop() {
        isOn = false
        journal.wasOn = false
        storage.save(journal)
        status = SyncStatus(state: .off)
        client.turnOff()
    }

    private func openStore() -> (any SyncStore)? {
        guard availability.isEntitled() else { return nil }
        if let store {
            return store
        }
        let made = makeStore()
        made.onExternalChange = { [weak self] change in self?.storeChanged(change) }
        store = made
        made.synchronize()
        return made
    }

    private func storeChanged(_ change: SyncStoreChange) {
        if change == .initialValues, isOn, acceptsInitialClear, let store {
            journal.clearedAt = max(journal.clearedAt, Self.clearedTime(in: store.all()))
            acceptsInitialClear = false
            storage.save(journal)
        }
        if change == .overQuota {
            isFull = true
        }
        refresh()
    }

    private static func clearedTime(in contents: [String: Any]) -> TimeInterval {
        contents[clearedKey].flatMap { SyncWire.decode($0, storeKey: clearedKey) }?.record.time ?? 0
    }

    /// A change made here after seeing a record is stamped later than it, whatever the other Mac's clock said.
    private func stamp(after known: TimeInterval?) -> TimeInterval {
        max(now().timeIntervalSince1970, (known ?? 0) + 0.001)
    }

    /// Notes what the app changed since the last look. Answers whether anything did.
    private func track() -> Bool {
        let snapshot = client.snapshot()
        var changed = false
        for (key, value) in snapshot {
            let digest = SyncWire.digest(value)
            guard journal.seen[key] != digest else { continue }
            let isUntouched = journal.records[key] == nil && client.defaults[key] == value
            journal.records[key] = SyncRecord(value: value, time: isUntouched ? 0 : stamp(after: journal.records[key]?.time), device: journal.device)
            journal.seen[key] = digest
            changed = true
        }
        for key in journal.seen.keys where snapshot[key] == nil {
            journal.records[key] = SyncRecord(value: nil, time: stamp(after: journal.records[key]?.time), device: journal.device)
            journal.seen[key] = nil
            changed = true
        }
        return changed
    }

    /// Hands the app the records that won from the store. Answers how many the app refused.
    private func take(_ outcome: inout SyncMerge.Outcome, from remote: [String: SyncRecord]) -> Int {
        guard !outcome.apply.isEmpty else { return 0 }
        var changed: [String: String] = [:]
        var removed: Set<String> = []
        for key in outcome.apply {
            if let value = remote[key]?.value {
                changed[key] = value
            } else if journal.seen[key] != nil {
                removed.insert(key)
            }
        }
        let refused = changed.isEmpty && removed.isEmpty ? [] : client.apply(changed, removed)
        let snapshot = client.snapshot()
        // A refused record is not noted, so it is tried and counted again until the other Mac repairs it.
        for key in outcome.apply.subtracting(refused) {
            journal.records[key] = remote[key]
            // What the app holds now, which is the same value unless it could keep only part of it.
            journal.seen[key] = snapshot[key].map(SyncWire.digest)
        }
        return refused.count
    }

    private func send(_ keys: Set<String>, to store: any SyncStore, holding remote: inout [String: SyncRecord]) {
        // An empty local cache is not proof that iCloud is empty. Untouched defaults never need uploading.
        let records = journal.records.filter { keys.contains($0.key) && $0.value.time != 0 }
        guard !records.isEmpty else {
            isFull = isFull && !SyncWire.fits(remote)
            return
        }
        let next = remote.merging(records) { _, mine in mine }
        isFull = !SyncWire.fits(next)
        guard !isFull else { return }
        for (key, record) in records {
            store.set(SyncWire.encode(record, key: key), for: SyncWire.storeKey(for: key))
        }
        store.synchronize()
        remote = next
    }

    private func forgetOldRemovals(in store: any SyncStore, holding remote: [String: SyncRecord]) {
        let expired = SyncMerge.expiredRemovals(in: journal.records, now: now())
        guard !expired.isEmpty else { return }
        for key in expired {
            journal.records[key] = nil
            if remote[key]?.isRemoval == true {
                store.remove(SyncWire.storeKey(for: key))
            }
        }
        store.synchronize()
    }
}
