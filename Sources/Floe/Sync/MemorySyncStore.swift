//
//  MemorySyncStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A stand-in for iCloud that tests join several stores to, to play several Macs. Nothing leaves the process.
final class MemorySyncCloud {
    fileprivate var values: [String: Any] = [:]
    fileprivate var stores: [MemorySyncStore] = []

    /// Hands every online store what the others uploaded, until nothing is left to hand over.
    func deliver() {
        // Each pass can make a store answer with writes of its own; the bound stops a pair that never agrees.
        for _ in 0 ..< 20 {
            let waiting = stores.filter { $0.isOnline && $0.needsDelivery }
            guard !waiting.isEmpty else { return }
            waiting.forEach { $0.receive() }
        }
    }

    fileprivate func upload(_ changes: [String: Any?], from sender: MemorySyncStore) {
        for (key, value) in changes {
            values[key] = value
        }
        for store in stores where store !== sender {
            store.needsDelivery = true
        }
    }
}

/// A `SyncStore` in memory: a local copy, and a cloud it exchanges with when asked and while online.
final class MemorySyncStore: SyncStore {
    private(set) var values: [String: Any] = [:]
    private var unsent: [String: Any?] = [:]
    private let cloud: MemorySyncCloud?
    fileprivate var needsDelivery = false
    private var hasReceived = false
    var onExternalChange: ((SyncStoreChange) -> Void)?
    /// Writes with a key longer than the real store takes. The real one drops them; here they are counted.
    private(set) var refusedKeys: [String] = []
    var isOnline = true {
        didSet {
            if isOnline, !oldValue {
                synchronize()
                needsDelivery = true
            }
        }
    }

    init(cloud: MemorySyncCloud? = nil) {
        self.cloud = cloud
        cloud?.stores.append(self)
        needsDelivery = cloud != nil
    }

    func all() -> [String: Any] {
        values
    }

    func set(_ value: [String: Any], for key: String) {
        guard key.utf8.count <= SyncWire.keyByteLimit else {
            refusedKeys.append(key)
            return
        }
        values[key] = value
        unsent[key] = .some(value)
    }

    /// Puts a value in as another program might have, to see what the engine does with it.
    func plant(_ value: Any, for key: String) {
        values[key] = value
    }

    func remove(_ key: String) {
        values[key] = nil
        unsent[key] = .some(nil)
    }

    @discardableResult
    func synchronize() -> Bool {
        guard isOnline, let cloud else { return false }
        if !unsent.isEmpty {
            cloud.upload(unsent, from: self)
            unsent = [:]
        }
        return true
    }

    fileprivate func receive() {
        guard let cloud else { return }
        needsDelivery = false
        // What is waiting to go up here is newer than the cloud's copy of it.
        var next = cloud.values
        for (key, value) in unsent {
            next[key] = value
        }
        let changed = NSDictionary(dictionary: next) != NSDictionary(dictionary: values)
        values = next
        let initial = !hasReceived
        hasReceived = true
        if changed || initial {
            onExternalChange?(initial ? .initialValues : .values)
        }
    }
}
