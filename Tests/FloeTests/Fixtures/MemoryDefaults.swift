//
//  MemoryDefaults.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Defaults that live only as long as the test: a suite of its own leaves a preferences file
/// behind, which macOS writes back even after the domain is removed.
/// The typed getters and setters of UserDefaults go through the overrides here.
final nonisolated class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { values }
    }

    override func removePersistentDomain(forName _: String) {
        lock.withLock { values.removeAll() }
    }

    override func synchronize() -> Bool {
        true
    }
}
