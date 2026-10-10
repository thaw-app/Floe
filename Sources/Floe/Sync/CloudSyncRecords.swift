//
//  CloudSyncRecords.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CloudKit
import Foundation

/// How a mirror entry becomes a CloudKit record, and how CloudKit's answers become events. Nothing here calls the server.
nonisolated struct CloudSyncRecordCoder: Sendable {
    /// The one field of a record: the value the engine wrote, as JSON text.
    static let field = "json"

    var zoneID = CKRecordZone.ID(zoneName: "Sync", ownerName: CKCurrentUserDefaultName)
    var recordType = "SyncRecord"

    func id(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    func isOurs(_ zone: CKRecordZone.ID) -> Bool {
        zone.zoneName == zoneID.zoneName
    }

    /// The record to save. It starts from the server's own fields when they are known, so the server sees no conflict.
    func record(named name: String, entry: CloudSyncEntry) -> CKRecord {
        let known = Self.restored(entry.system).flatMap { $0.recordType == recordType && $0.recordID.recordName == name ? $0 : nil }
        let record = known ?? CKRecord(recordType: recordType, recordID: id(name))
        record[Self.field] = entry.json
        return record
    }

    func entry(of record: CKRecord) -> CloudSyncEntry {
        CloudSyncEntry(json: record[Self.field] as? String, system: Self.system(of: record))
    }

    static func system(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func restored(_ system: Data?) -> CKRecord? {
        guard let system, let coder = try? NSKeyedUnarchiver(forReadingFrom: system) else { return nil }
        coder.requiresSecureCoding = true
        return CKRecord(coder: coder)
    }

    func fetched(modified: [CKRecord], deleted: [CKRecord.ID]) -> CloudSyncEvent {
        .fetched(changed: entries(modified), deleted: deleted.filter { isOurs($0.zoneID) }.map(\.recordName))
    }

    func sent(saved: [CKRecord], deleted: [CKRecord.ID], failedSaves: [CKRecord.ID: CKError], failedDeletes: [CKRecord.ID: CKError]) -> CloudSyncEvent {
        .sent(
            saved: entries(saved),
            deleted: deleted.filter { isOurs($0.zoneID) }.map(\.recordName),
            failedSaves: failures(failedSaves),
            failedDeletes: failures(failedDeletes)
        )
    }

    func failure(for error: CKError, item: AnyHashable? = nil) -> CloudSyncFailure {
        switch error.code {
        case .serverRecordChanged: .conflict(error.serverRecord.map(entry))
        case .zoneNotFound: .zoneMissing
        case .userDeletedZone: .zonePurged
        case .unknownItem: .unknownItem
        case .quotaExceeded: .quotaExceeded
        case .batchRequestFailed: .batch
        case .invalidArguments, .serverRejectedRequest, .permissionFailure, .constraintViolation: .refused
        case .partialFailure:
            // The request's error holds one error for each item that failed; an item it does not name was not at fault.
            (item.flatMap { error.partialErrorsByItemID?[$0] } as? CKError).map { failure(for: $0) } ?? .batch
        default: .later
        }
    }

    static func loss(_ reason: CKDatabase.DatabaseChange.Deletion.Reason) -> CloudSyncZoneLoss {
        switch reason {
        case .purged: .purged
        case .encryptedDataReset: .keysReset
        default: .deleted
        }
    }

    private func entries(_ records: [CKRecord]) -> [String: CloudSyncEntry] {
        let ours = records.filter { isOurs($0.recordID.zoneID) && $0.recordType == recordType }
        return Dictionary(ours.map { ($0.recordID.recordName, entry(of: $0)) }) { _, last in last }
    }

    private func failures(_ errors: [CKRecord.ID: CKError]) -> [String: CloudSyncFailure] {
        let ours = errors.filter { isOurs($0.key.zoneID) }
        return Dictionary(ours.map { ($0.key.recordName, failure(for: $0.value, item: $0.key)) }) { _, last in last }
    }
}
