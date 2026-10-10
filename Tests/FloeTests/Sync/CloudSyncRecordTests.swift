//
//  CloudSyncRecordTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CloudKit
@testable import Floe
import Foundation
import Testing

/// Records and errors are made here as plain objects. No container is opened and nothing is sent.
struct CloudSyncRecordTests {
    private let coder = CloudSyncRecordCoder()

    private func record(_ name: String, json: String?, type: String = "SyncRecord", zone: String = "Sync") -> CKRecord {
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)))
        record[CloudSyncRecordCoder.field] = json
        return record
    }

    @Test func aRecordHoldsTheValueAsTheEngineWroteItAndNothingElse() {
        let value = SyncWire.encode(SyncRecord(value: "\"saf\"", time: 2000.5, device: "a"), key: "alias", in: .cloudKit)
        let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
        let json = String(decoding: data ?? Data(), as: UTF8.self)
        let made = coder.record(named: "alias", entry: CloudSyncEntry(json: json, system: nil))
        #expect(made.recordType == "SyncRecord")
        #expect(made.recordID.recordName == "alias")
        #expect(made.recordID.zoneID.zoneName == "Sync")
        #expect(made.allKeys() == ["json"])
        let back = coder.entry(of: made)
        #expect(back.json == json)
        let mirror = SyncMirror(server: ["alias": back], hasFetched: true)
        let decoded = SyncWire.decode(CloudSyncCore(mirror: mirror, hasSavedState: true).contents, in: .cloudKit)
        #expect(decoded.records == ["alias": SyncRecord(value: "\"saf\"", time: 2000.5, device: "a")])
        #expect(decoded.skipped == 0)
    }

    @Test func theServersFieldsAreKeptForTheNextSave() throws {
        let fetched = record("alias", json: "1")
        let entry = coder.entry(of: fetched)
        let restored = try #require(CloudSyncRecordCoder.restored(entry.system))
        #expect(restored.recordID == fetched.recordID)
        #expect(restored.recordType == "SyncRecord")
        #expect(restored.allKeys().isEmpty, "only the server's own fields are kept, not the value")
        let next = coder.record(named: "alias", entry: CloudSyncEntry(json: "2", system: entry.system))
        #expect(next.recordID == fetched.recordID)
        #expect(next[CloudSyncRecordCoder.field] as? String == "2")
    }

    @Test func fieldsOfAnotherRecordOrNoneAtAllStartANewRecord() {
        let other = coder.entry(of: record("other", json: "1")).system
        #expect(coder.record(named: "alias", entry: CloudSyncEntry(json: "2", system: other)).recordID.recordName == "alias")
        #expect(coder.record(named: "alias", entry: CloudSyncEntry(json: "2", system: Data("garbage".utf8))).recordID.recordName == "alias")
        let foreign = coder.entry(of: record("alias", json: "1", type: "Other")).system
        #expect(coder.record(named: "alias", entry: CloudSyncEntry(json: "2", system: foreign)).recordType == "SyncRecord")
        #expect(CloudSyncRecordCoder.restored(nil) == nil)
    }

    @Test func fetchedChangesOfOtherZonesAndTypesAreLeftOut() {
        let records = [record("alias", json: "1"), record("elsewhere", json: "2", zone: "Other"), record("foreign", json: "3", type: "Other"), record("empty", json: nil)]
        let deleted = [coder.id("gone"), record("elsewhere", json: nil, zone: "Other").recordID]
        guard case let .fetched(changed, removed) = coder.fetched(modified: records, deleted: deleted) else {
            Issue.record("not a fetch")
            return
        }
        #expect(changed.keys.sorted() == ["alias", "empty"])
        #expect(changed["alias"]?.json == "1")
        #expect(changed["empty"]?.json == nil)
        #expect(removed == ["gone"])
    }

    @Test func aSentBatchBecomesOneEventWithEachRecordsOwnResult() {
        let server = record("newer", json: "9")
        let conflict = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
        let event = coder.sent(
            saved: [record("saved", json: "1")],
            deleted: [coder.id("deleted")],
            failedSaves: [coder.id("newer"): conflict, coder.id("full"): CKError(.quotaExceeded)],
            failedDeletes: [coder.id("gone"): CKError(.unknownItem)]
        )
        guard case let .sent(saved, deleted, failedSaves, failedDeletes) = event else {
            Issue.record("not a send")
            return
        }
        #expect(saved.keys.sorted() == ["saved"])
        #expect(deleted == ["deleted"])
        #expect(failedSaves == ["newer": .conflict(coder.entry(of: server)), "full": .quotaExceeded])
        #expect(failedDeletes == ["gone": .unknownItem])
    }

    @Test func cloudKitsErrorsBecomeTheFailuresTheStoreKnows() {
        #expect(coder.failure(for: CKError(.serverRecordChanged)) == .conflict(nil))
        #expect(coder.failure(for: CKError(.zoneNotFound)) == .zoneMissing)
        #expect(coder.failure(for: CKError(.userDeletedZone)) == .zonePurged)
        #expect(coder.failure(for: CKError(.unknownItem)) == .unknownItem)
        #expect(coder.failure(for: CKError(.quotaExceeded)) == .quotaExceeded)
        #expect(coder.failure(for: CKError(.batchRequestFailed)) == .batch)
        for code in [CKError.Code.networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .requestRateLimited, .internalError] {
            #expect(coder.failure(for: CKError(code)) == .later)
        }
        for code in [CKError.Code.invalidArguments, .serverRejectedRequest, .permissionFailure, .constraintViolation] {
            #expect(coder.failure(for: CKError(code)) == .refused)
        }
    }

    @Test func aPartialFailureIsReadForTheItemItNames() {
        let id = coder.id("alias")
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [id: CKError(.quotaExceeded) as NSError]])
        #expect(coder.failure(for: partial, item: id) == .quotaExceeded)
        #expect(coder.failure(for: partial, item: coder.id("other")) == .batch)
        #expect(coder.failure(for: partial) == .batch)
    }

    @Test func theReasonAZoneWentAwayIsKept() {
        #expect(CloudSyncRecordCoder.loss(.deleted) == .deleted)
        #expect(CloudSyncRecordCoder.loss(.purged) == .purged)
        #expect(CloudSyncRecordCoder.loss(.encryptedDataReset) == .keysReset)
    }
}
