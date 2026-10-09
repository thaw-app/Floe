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
}

/// The key-value store the records are kept in. The app uses iCloud's; tests use one in memory.
protocol SyncStore: AnyObject {
    /// Everything in the store, as it holds it. Values are not trusted to be records.
    func all() -> [String: Any]
    func set(_ value: [String: Any], for key: String)
    func remove(_ key: String)
    /// Asks the store to exchange with its server soon. False when it could not.
    @discardableResult
    func synchronize() -> Bool
    var onExternalChange: ((SyncStoreChange) -> Void)? { get set }
}

/// How a record is written into the store, and how much room the records take there.
nonisolated enum SyncWire {
    /// iCloud's key-value store takes 1 MB in all, 1024 keys, and keys of at most 64 bytes.
    static let byteLimit = 1024 * 1024
    static let keyLimit = 1024
    static let keyByteLimit = 64
    /// Writing stops at this share of each limit, so the store never refuses a write by itself.
    static let safeShare = 0.9

    static var byteBudget: Int {
        Int(Double(byteLimit) * safeShare)
    }

    static var keyBudget: Int {
        Int(Double(keyLimit) * safeShare)
    }

    private static let keyField = "k"
    private static let timeField = "t"
    private static let deviceField = "d"
    private static let valueField = "v"

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The record's key when the store can take it, otherwise a digest of it; the record then carries the key.
    static func storeKey(for key: String) -> String {
        key.utf8.count <= keyByteLimit ? key : "#" + digest(key)
    }

    static func encode(_ record: SyncRecord, key: String) -> [String: Any] {
        var fields: [String: Any] = [timeField: record.time, deviceField: record.device]
        if let value = record.value {
            fields[valueField] = value
        }
        if storeKey(for: key) != key {
            fields[keyField] = key
        }
        return fields
    }

    /// The record in a stored value, or nil for anything that is not one.
    static func decode(_ stored: Any, storeKey: String) -> (key: String, record: SyncRecord)? {
        guard let fields = stored as? [String: Any],
              let time = fields[timeField] as? Double, time.isFinite,
              let device = fields[deviceField] as? String, !device.isEmpty
        else { return nil }
        let key = fields[keyField] as? String ?? storeKey
        guard fields[keyField] == nil || fields[keyField] is String, Self.storeKey(for: key) == storeKey else { return nil }
        guard let stored = fields[valueField] else {
            return (key, SyncRecord(value: nil, time: time, device: device))
        }
        guard let text = stored as? String, isJSON(text) else { return nil }
        return (key, SyncRecord(value: text, time: time, device: device))
    }

    /// The records in a store's contents, and how many of its values were not records.
    static func decode(_ contents: [String: Any]) -> (records: [String: SyncRecord], skipped: Int) {
        var records: [String: SyncRecord] = [:]
        var skipped = 0
        for (storeKey, stored) in contents {
            if let (key, record) = decode(stored, storeKey: storeKey) {
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

    /// The bytes the records take in the store, counted generously: keys, values, device ids and the stamps.
    static func size(of records: [String: SyncRecord]) -> Int {
        records.reduce(0) { total, entry in
            let key = entry.key.utf8.count
            let carried = storeKey(for: entry.key) == entry.key ? 0 : key
            return total + min(key, keyByteLimit) + carried + (entry.value.value?.utf8.count ?? 0) + entry.value.device.utf8.count + 32
        }
    }

    static func fits(_ records: [String: SyncRecord]) -> Bool {
        records.count <= keyBudget && size(of: records) <= byteBudget
    }
}
