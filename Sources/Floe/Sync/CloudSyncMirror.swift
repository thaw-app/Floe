//
//  CloudSyncMirror.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One record as the server holds it.
nonisolated struct CloudSyncEntry: Codable, Equatable, Sendable {
    /// The stored value as JSON text. Nil when the record holds none.
    var json: String?
    /// The server's own fields of the record, which the next save of it must carry to be accepted.
    var system: Data?
}

/// This Mac's copy of what iCloud holds, kept on disk because the store is asked without waiting.
nonisolated struct SyncMirror: Codable, Equatable, Sendable {
    /// A change not yet sent. Nil text is a deletion.
    struct Change: Codable, Equatable, Sendable {
        var json: String?
    }

    /// What the server is known to hold, by record name.
    var server: [String: CloudSyncEntry] = [:]
    var pending: [String: Change] = [:]
    /// Pending changes the server will never take. They wait for a new value and are not sent again.
    var refused: Set<String> = []
    /// The iCloud user the mirror belongs to.
    var account: String?
    var zoneExists = false
    /// False until a fetch has finished, and again while the zone must be read anew. Nothing is sent meanwhile.
    var hasFetched = false
    /// True from "remove from iCloud" until the server confirms the zone is gone. Nothing is sent meanwhile.
    var isClearing = false
}

/// Where the mirror and the system sync engine's own state are kept between launches.
struct CloudSyncFiles {
    var loadMirror: () -> SyncMirror?
    var saveMirror: (SyncMirror) -> Void
    var loadState: () -> Data?
    /// Nil deletes the saved state.
    var saveState: (Data?) -> Void

    static func folder(_ folder: URL) -> CloudSyncFiles {
        let mirror = folder.appendingPathComponent("SyncMirror.json")
        let state = folder.appendingPathComponent("SyncState.json")
        return CloudSyncFiles(
            loadMirror: { (try? Data(contentsOf: mirror)).flatMap { try? JSONDecoder().decode(SyncMirror.self, from: $0) } },
            saveMirror: { value in
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? JSONEncoder().encode(value).write(to: mirror, options: .atomic)
            },
            loadState: { try? Data(contentsOf: state) },
            saveState: { data in
                guard let data else {
                    try? FileManager.default.removeItem(at: state)
                    return
                }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? data.write(to: state, options: .atomic)
            }
        )
    }
}

/// The CloudKit store without CloudKit: the mirror, what waits to be sent, and what each event does to them.
nonisolated struct CloudSyncCore {
    private(set) var mirror: SyncMirror
    /// True from a save refused for lack of room in the account until one is taken again.
    private(set) var isOverQuota = false
    /// Whether fetched changes altered the contents since the engine was last told.
    private var hasNews = false
    /// False when the system engine's saved state must not be used, because the mirror it went with is gone.
    let keepsSavedState: Bool

    init(mirror saved: SyncMirror?, hasSavedState: Bool) {
        var mirror = saved ?? SyncMirror()
        keepsSavedState = saved != nil && hasSavedState
        if !keepsSavedState {
            // The next fetch starts from nothing and reports no deletions, so what the server held is unknown again.
            mirror.server = [:]
            mirror.hasFetched = false
            mirror.zoneExists = false
        }
        self.mirror = mirror
    }

    /// What the store answers with: the server's records with the waiting changes laid over them.
    var contents: [String: Any] {
        texts.mapValues(Self.value)
    }

    var limits: SyncLimits {
        var limits = SyncLimits.cloudKit
        limits.isExhausted = isOverQuota
        return limits
    }

    private var texts: [String: String] {
        var texts = mirror.server.mapValues { $0.json ?? "" }
        for (name, change) in mirror.pending {
            texts[name] = change.json
        }
        return texts
    }

    private var canSend: Bool {
        mirror.hasFetched && !mirror.isClearing
    }

    /// The fields the engine wrote, or the text itself when it is not such a value, which the engine then skips.
    private static func value(_ json: String) -> Any {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? json
    }

    mutating func set(_ json: String, for name: String) -> [CloudSyncCommand] {
        mirror.refused.remove(name)
        if mirror.pending[name] == nil, mirror.server[name]?.json == json {
            return []
        }
        mirror.pending[name] = SyncMirror.Change(json: json)
        return queue([name])
    }

    mutating func remove(_ name: String) -> [CloudSyncCommand] {
        mirror.refused.remove(name)
        guard mirror.server[name] != nil || mirror.pending[name] != nil else { return [] }
        // Queued even for a record never confirmed: its save may be on the way to the server.
        mirror.pending[name] = SyncMirror.Change(json: nil)
        return queue([name])
    }

    /// Deletes the zone. Whatever is set from here on waits until the server confirms, then goes into a new zone.
    mutating func removeAll() -> [CloudSyncCommand] {
        mirror.server = [:]
        mirror.pending = [:]
        mirror.refused = []
        mirror.zoneExists = false
        mirror.isClearing = true
        isOverQuota = false
        return [.forgetEverything, .deleteZone]
    }

    /// Everything that waits, to queue again at launch and at each exchange. Queuing twice does no harm.
    func resend() -> [CloudSyncCommand] {
        mirror.isClearing ? [.deleteZone] : queue(mirror.pending.keys)
    }

    /// What to save for a record the system engine is about to send. Nil when nothing waits for it any more.
    func outgoing(_ name: String) -> CloudSyncEntry? {
        guard canSend, !mirror.refused.contains(name), let json = mirror.pending[name]?.json else { return nil }
        return CloudSyncEntry(json: json, system: mirror.server[name]?.system)
    }

    mutating func handle(_ event: CloudSyncEvent) -> CloudSyncEffects {
        var effects = CloudSyncEffects()
        switch event {
        case let .fetched(changed, deleted): fetched(changed, deleted: deleted, &effects)
        case .fetchFinished: fetchFinished(&effects)
        case let .sent(saved, deleted, failedSaves, failedDeletes):
            sent(saved, deleted: deleted, &effects)
            failed(saves: failedSaves, deletes: failedDeletes, &effects)
        case let .signedIn(user): signedIn(user, &effects)
        case .signedOut: newAccount(nil, &effects)
        case let .switchedAccount(user): newAccount(user, &effects)
        default: zoneChanged(event, &effects)
        }
        return effects
    }

    private mutating func zoneChanged(_ event: CloudSyncEvent, _ effects: inout CloudSyncEffects) {
        switch event {
        case .zoneSaved: mirror.zoneExists = true
        case .zoneSaveFailed(.quotaExceeded):
            isOverQuota = true
            effects.note(.overQuota)
        case .zoneDeletionSent, .zoneDeletionFailed(.zoneMissing), .zoneDeletionFailed(.zonePurged), .zoneDeletionFailed(.unknownItem):
            // This Mac's own deletion went through, or the zone was gone: what was set since goes into a zone made anew.
            mirror.isClearing = false
            mirror.zoneExists = false
            effects.commands += resend()
        case let .zoneLost(loss): zoneLost(loss, &effects)
        default: break
        }
    }

    private func queue(_ names: some Sequence<String>) -> [CloudSyncCommand] {
        guard canSend else { return [] }
        let changes: [CloudSyncCommand] = names.sorted().compactMap { name in
            guard !mirror.refused.contains(name), let change = mirror.pending[name] else { return nil }
            return change.json == nil ? .delete(name) : .save(name)
        }
        guard !changes.isEmpty else { return [] }
        return (mirror.zoneExists ? [] : [.saveZone]) + changes
    }

    private mutating func fetched(_ changed: [String: CloudSyncEntry], deleted: [String], _ effects: inout CloudSyncEffects) {
        // Records of a zone this Mac is deleting are not taken in again.
        guard !mirror.isClearing else { return }
        let before = texts
        mirror.zoneExists = true
        for (name, entry) in changed {
            mirror.server[name] = entry
            mirror.refused.remove(name)
            // The server's record replaces what waited: the engine sees it and sends this Mac's again if that is newer.
            if mirror.pending.removeValue(forKey: name) != nil {
                effects.commands.append(.forget(name))
            }
        }
        for name in deleted {
            mirror.server[name] = nil
        }
        hasNews = hasNews || texts != before
    }

    /// The engine is told once per fetch, so it never merges with half of what the server holds.
    private mutating func fetchFinished(_ effects: inout CloudSyncEffects) {
        let isFirst = !mirror.hasFetched
        mirror.hasFetched = true
        if isFirst {
            effects.commands += resend()
            effects.note(.initialValues)
        } else if hasNews {
            effects.note(.values)
        }
        hasNews = false
    }

    private mutating func sent(_ saved: [String: CloudSyncEntry], deleted: [String], _ effects: inout CloudSyncEffects) {
        var again: [String] = []
        for (name, entry) in saved {
            mirror.zoneExists = true
            mirror.server[name] = entry
            if let change = mirror.pending[name], change.json != nil, change.json == entry.json {
                mirror.pending[name] = nil
            } else {
                // Changed again while the save was on its way.
                again.append(name)
            }
        }
        for name in deleted {
            mirror.server[name] = nil
            forgetDeletion(of: name)
        }
        // A value set while its record's deletion was on the way.
        again += deleted
        if !saved.isEmpty, isOverQuota {
            isOverQuota = false
            effects.note(.values)
        }
        effects.commands += queue(again)
    }

    private mutating func forgetDeletion(of name: String) {
        if let change = mirror.pending[name], change.json == nil {
            mirror.pending[name] = nil
        }
    }

    private mutating func failed(saves: [String: CloudSyncFailure], deletes: [String: CloudSyncFailure], _ effects: inout CloudSyncEffects) {
        let again = saves.keys.sorted().filter { failedSave($0, saves[$0] ?? .later, &effects) }
        for (name, failure) in deletes where [.unknownItem, .zoneMissing, .zonePurged].contains(failure) {
            // Gone already, which is what the deletion asked for.
            mirror.server[name] = nil
            forgetDeletion(of: name)
        }
        effects.commands += queue(again)
    }

    /// Answers whether the save is to be queued again.
    private mutating func failedSave(_ name: String, _ failure: CloudSyncFailure, _ effects: inout CloudSyncEffects) -> Bool {
        switch failure {
        case let .conflict(entry?):
            // No rule of its own here: the engine sees the server's record and decides by age, as for any other.
            mirror.server[name] = entry
            mirror.pending[name] = nil
            effects.note(.values)
        case .conflict(nil), .unknownItem:
            mirror.server[name] = nil
            return true
        case .zoneMissing:
            guard mirror.zoneExists else { return true }
            zoneLost(.deleted, &effects)
        case .zonePurged:
            zoneLost(.purged, &effects)
        case .quotaExceeded:
            isOverQuota = true
            effects.note(.overQuota)
        case .batch:
            return true
        case .later:
            break
        case .refused:
            mirror.refused.insert(name)
        }
        return false
    }

    private mutating func zoneLost(_ loss: CloudSyncZoneLoss, _ effects: inout CloudSyncEffects) {
        mirror.server = [:]
        mirror.zoneExists = false
        effects.commands.append(.forgetEverything)
        if loss == .purged {
            mirror.pending = [:]
            mirror.refused = []
            mirror.isClearing = false
            effects.note(.removed)
            return
        }
        // Held until the fetch ends: a Mac that removed the copy leaves a note in the new zone, which must be read first.
        mirror.hasFetched = false
        hasNews = true
        effects.commands.append(.fetch)
    }

    private mutating func signedIn(_ user: String, _ effects: inout CloudSyncEffects) {
        guard mirror.account == nil || mirror.account == user else {
            newAccount(user, &effects)
            return
        }
        mirror.account = user
        effects.note(.account)
    }

    /// The mirror was the old account's. The app's values are not touched and go up to the new one as a first sync.
    private mutating func newAccount(_ user: String?, _ effects: inout CloudSyncEffects) {
        mirror = SyncMirror(account: user)
        isOverQuota = false
        hasNews = false
        effects.commands.append(.restart)
        effects.note(.account)
    }
}
