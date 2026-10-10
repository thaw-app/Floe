//
//  SyncStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
import Foundation

/// Why a store says its contents changed without this process writing them.
nonisolated enum SyncStoreChange: Equatable, Sendable {
    /// Another device's values arrived after the initial download.
    case values
    /// The first download, which may contain a clear marker made before this device joined.
    case initialValues
    /// The store refused a write because it is over its limits.
    case overQuota
    /// A different iCloud account is signed in, or none.
    case account
    /// The user deleted the store's contents outside the app, which no device should put back.
    case removed
}

/// The store the records are kept in. The app uses one of iCloud's; tests use one in memory.
protocol SyncStore: AnyObject {
    /// Everything in the store, as it holds it. Values are not trusted to be records.
    func all() -> [String: Any]
    func set(_ value: [String: Any], for key: String)
    func remove(_ key: String)
    /// Empties the store, when the user removes the copy in iCloud. A store may have a cheaper way than key by key.
    func removeAll()
    /// Asks the store to exchange with its server soon. False when it could not.
    @discardableResult
    func synchronize() -> Bool
    /// What the store takes right now. Asked before every write.
    var limits: SyncLimits { get }
    var onExternalChange: ((SyncStoreChange) -> Void)? { get set }
}

extension SyncStore {
    func removeAll() {
        for key in all().keys {
            remove(key)
        }
    }
}

/// How much a store takes and which keys it takes as they are. Each store has its own.
nonisolated struct SyncLimits: Equatable, Sendable {
    /// The bytes all records may take together, where the store counts them.
    var bytes: Int?
    /// The number of records, where the store counts them.
    var keys: Int?
    /// The bytes one record may take, where the store limits a record.
    var recordBytes: Int?
    /// The bytes a key may take. A longer one is stored under a digest.
    var keyBytes: Int
    /// Whether a key must be printable ASCII. Any other is stored under a digest.
    var asciiKeys = false
    /// Set while the store refuses every write, as an iCloud account without room does.
    var isExhausted = false

    /// Writing stops at this share of each limit, so the store never refuses a write by itself.
    static let safeShare = 0.9

    /// iCloud's key-value store takes 1 MB in all, 1024 keys, and keys of at most 64 bytes.
    static let keyValueStore = SyncLimits(bytes: budget(1024 * 1024), keys: budget(1024), keyBytes: 64)
    /// CloudKit takes about 1 MB in a record and a record name of 255 ASCII characters, and counts no records.
    static let cloudKit = SyncLimits(recordBytes: budget(1024 * 1024), keyBytes: 255, asciiKeys: true)

    static func budget(_ limit: Int) -> Int {
        Int(Double(limit) * safeShare)
    }

    /// Whether the store takes this key as it is. CloudKit refuses an empty name and one with a leading underscore.
    func takes(key: String) -> Bool {
        guard key.utf8.count <= keyBytes else { return false }
        return !asciiKeys || (!key.isEmpty && !key.hasPrefix("_") && key.utf8.allSatisfy { (0x20 ... 0x7E).contains($0) })
    }

    /// The bytes one record takes in the store, counted generously: key, value, device id and the stamp.
    func size(of record: SyncRecord, key: String) -> Int {
        let length = key.utf8.count
        let stored = takes(key: key) ? length : min(length, keyBytes) + length
        return stored + (record.value?.utf8.count ?? 0) + record.device.utf8.count + 32
    }

    func size(of records: [String: SyncRecord]) -> Int {
        records.reduce(0) { $0 + size(of: $1.value, key: $1.key) }
    }

    func fits(_ records: [String: SyncRecord]) -> Bool {
        guard !isExhausted, records.count <= keys ?? .max, size(of: records) <= bytes ?? .max else { return false }
        guard let recordBytes else { return true }
        return !records.contains { size(of: $0.value, key: $0.key) > recordBytes }
    }
}

/// How a record is written into a store.
nonisolated enum SyncWire {
    private static let keyField = "k"
    private static let timeField = "t"
    private static let deviceField = "d"
    private static let valueField = "v"

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The record's key when the store can take it, otherwise a digest of it; the record then carries the key.
    static func storeKey(for key: String, in limits: SyncLimits = .keyValueStore) -> String {
        limits.takes(key: key) ? key : "#" + digest(key)
    }

    static func encode(_ record: SyncRecord, key: String, in limits: SyncLimits = .keyValueStore) -> [String: Any] {
        var fields: [String: Any] = [timeField: record.time, deviceField: record.device]
        if let value = record.value {
            fields[valueField] = value
        }
        if storeKey(for: key, in: limits) != key {
            fields[keyField] = key
        }
        return fields
    }

    /// The record in a stored value, or nil for anything that is not one.
    static func decode(_ stored: Any, storeKey: String, in limits: SyncLimits = .keyValueStore) -> (key: String, record: SyncRecord)? {
        guard let fields = stored as? [String: Any],
              let time = fields[timeField] as? Double, time.isFinite,
              let device = fields[deviceField] as? String, !device.isEmpty
        else { return nil }
        let key = fields[keyField] as? String ?? storeKey
        guard fields[keyField] == nil || fields[keyField] is String, Self.storeKey(for: key, in: limits) == storeKey else { return nil }
        guard let stored = fields[valueField] else {
            return (key, SyncRecord(value: nil, time: time, device: device))
        }
        guard let text = stored as? String, isJSON(text) else { return nil }
        return (key, SyncRecord(value: text, time: time, device: device))
    }

    /// The records in a store's contents, and how many of its values were not records.
    static func decode(_ contents: [String: Any], in limits: SyncLimits = .keyValueStore) -> (records: [String: SyncRecord], skipped: Int) {
        var records: [String: SyncRecord] = [:]
        var skipped = 0
        for (storeKey, stored) in contents {
            if let (key, record) = decode(stored, storeKey: storeKey, in: limits) {
                records[key] = record
            } else {
                skipped += 1
            }
        }
        return (records, skipped)
    }

    static func isJSON(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) != nil
    }
}
