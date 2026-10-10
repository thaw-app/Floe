//
//  CloudKitSyncStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CloudKit
import Foundation

/// iCloud's private database as a `SyncStore`, through the system's sync engine. Made only once the build is known
/// to be signed for the container. The decisions are `CloudSyncCore`'s; this passes them on.
final class CloudKitSyncStore: SyncStore {
    private var core: CloudSyncCore
    private var saved: SyncMirror?
    private let files: CloudSyncFiles
    private let coder: CloudSyncRecordCoder
    private let container: CKContainer
    private let account: CloudSyncAccount
    private var engine: CKSyncEngine?
    private var exchange: Task<Void, Never>?
    var onExternalChange: ((SyncStoreChange) -> Void)?

    var limits: SyncLimits {
        core.limits
    }

    init(container identifier: String, files: CloudSyncFiles, account: CloudSyncAccount, coder: CloudSyncRecordCoder = CloudSyncRecordCoder()) {
        self.files = files
        self.account = account
        self.coder = coder
        container = CKContainer(identifier: identifier)
        let state = files.loadState().flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        saved = files.loadMirror()
        core = CloudSyncCore(mirror: saved, hasSavedState: state != nil)
        start(with: core.keepsSavedState ? state : nil)
        apply(CloudSyncEffects(commands: core.resend()))
        Task { await self.readAccount() }
    }

    func all() -> [String: Any] {
        core.contents
    }

    func set(_ value: [String: Any], for key: String) {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys),
              let json = String(data: data, encoding: .utf8)
        else { return }
        apply(CloudSyncEffects(commands: core.set(json, for: key)))
    }

    func remove(_ key: String) {
        apply(CloudSyncEffects(commands: core.remove(key)))
    }

    func removeAll() {
        apply(CloudSyncEffects(commands: core.removeAll()))
    }

    /// Queues what waits once more, then fetches and sends now. The system engine also does both on its own schedule.
    @discardableResult
    func synchronize() -> Bool {
        guard let engine else { return false }
        apply(CloudSyncEffects(commands: core.resend()))
        guard exchange == nil else { return true }
        exchange = Task { [weak self] in
            try? await engine.fetchChanges()
            try? await engine.sendChanges()
            self?.exchange = nil
        }
        return true
    }

    private func start(with state: CKSyncEngine.State.Serialization?) {
        if state == nil {
            files.saveState(nil)
        }
        engine = CKSyncEngine(CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: state, delegate: self))
    }

    /// The sync engine reports an account only when it changes, so the first answer is asked for.
    private func readAccount() async {
        guard let status = try? await container.accountStatus() else { return }
        guard (status == .available) != account.isSignedIn else { return }
        account.isSignedIn = status == .available
        onExternalChange?(.account)
    }

    private func apply(_ effects: CloudSyncEffects) {
        if core.mirror != saved {
            saved = core.mirror
            files.saveMirror(core.mirror)
        }
        effects.commands.forEach(run)
        if let change = effects.change {
            onExternalChange?(change)
        }
    }

    private func run(_ command: CloudSyncCommand) {
        guard let state = engine?.state else { return }
        switch command {
        case let .save(name):
            state.remove(pendingRecordZoneChanges: [.deleteRecord(coder.id(name))])
            state.add(pendingRecordZoneChanges: [.saveRecord(coder.id(name))])
        case let .delete(name):
            state.remove(pendingRecordZoneChanges: [.saveRecord(coder.id(name))])
            state.add(pendingRecordZoneChanges: [.deleteRecord(coder.id(name))])
        case let .forget(name):
            state.remove(pendingRecordZoneChanges: [.saveRecord(coder.id(name)), .deleteRecord(coder.id(name))])
        case .forgetEverything:
            state.remove(pendingRecordZoneChanges: state.pendingRecordZoneChanges)
            state.remove(pendingDatabaseChanges: state.pendingDatabaseChanges)
        case .saveZone:
            state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: coder.zoneID))])
        case .deleteZone:
            state.add(pendingDatabaseChanges: [.deleteZone(coder.zoneID)])
        case .restart:
            start(with: nil)
        case .fetch:
            // Not awaited: the sync engine hands over its next event only after this one returns.
            Task { [engine] in try? await engine?.fetchChanges() }
        }
    }

    private func take(_ event: CloudSyncEvent) {
        apply(core.handle(event))
    }

    private func handle(_ event: CKSyncEngine.Event, from source: CKSyncEngine) {
        // An engine replaced after an account change may still report; its account's events are not this one's.
        guard source === engine else { return }
        switch event {
        case let .stateUpdate(update):
            files.saveState(try? JSONEncoder().encode(update.stateSerialization))
        case let .accountChange(change):
            accountChanged(change.changeType)
        case let .fetchedDatabaseChanges(changes):
            for deletion in changes.deletions where coder.isOurs(deletion.zoneID) {
                take(.zoneLost(CloudSyncRecordCoder.loss(deletion.reason)))
            }
        case let .fetchedRecordZoneChanges(changes):
            take(coder.fetched(modified: changes.modifications.map(\.record), deleted: changes.deletions.map(\.recordID)))
        case let .sentDatabaseChanges(sent):
            zoneChangesSent(sent)
        case let .sentRecordZoneChanges(sent):
            let failedSaves = Dictionary(sent.failedRecordSaves.map { ($0.record.recordID, $0.error) }) { _, last in last }
            take(coder.sent(saved: sent.savedRecords, deleted: sent.deletedRecordIDs, failedSaves: failedSaves, failedDeletes: sent.failedRecordDeletes))
        case .didFetchChanges:
            take(.fetchFinished)
        default:
            break
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        switch change {
        case let .signIn(user):
            account.isSignedIn = true
            take(.signedIn(user.recordName))
        case .signOut:
            account.isSignedIn = false
            take(.signedOut)
        case let .switchAccounts(_, user):
            account.isSignedIn = true
            take(.switchedAccount(user.recordName))
        @unknown default:
            break
        }
    }

    private func zoneChangesSent(_ sent: CKSyncEngine.Event.SentDatabaseChanges) {
        if sent.savedZones.contains(where: { coder.isOurs($0.zoneID) }) {
            take(.zoneSaved)
        }
        if sent.deletedZoneIDs.contains(where: coder.isOurs) {
            take(.zoneDeletionSent)
        }
        for failed in sent.failedZoneSaves where coder.isOurs(failed.zone.zoneID) {
            take(.zoneSaveFailed(coder.failure(for: failed.error, item: failed.zone.zoneID)))
        }
        for (zone, error) in sent.failedZoneDeletes where coder.isOurs(zone) {
            take(.zoneDeletionFailed(coder.failure(for: error, item: zone)))
        }
    }

    private func outgoing(_ changes: [CKSyncEngine.PendingRecordZoneChange]) -> [CKRecord.ID: CKRecord] {
        var records: [CKRecord.ID: CKRecord] = [:]
        for case let .saveRecord(id) in changes {
            records[id] = core.outgoing(id.recordName).map { coder.record(named: id.recordName, entry: $0) }
        }
        return records
    }
}

extension CloudKitSyncStore: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, from: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let records = await outgoing(changes)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            if records[id] == nil {
                // Nothing waits for this record any more, so the system engine is told to stop asking.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            }
            return records[id]
        }
    }
}
