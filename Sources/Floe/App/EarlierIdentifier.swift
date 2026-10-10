//
//  EarlierIdentifier.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Floe was `com.thaw.floe` before it was `org.thaw.floe`. What it stored under the earlier name is taken over.
nonisolated enum EarlierIdentifier {
    static let current = "org.thaw.floe"
    static let earlier = "com.thaw.floe"
    static let secretService = "com.thaw.floe.preferences"
    static let importedKey = "importedEarlierIdentifier"

    /// Run before anything reads the defaults. A copy without an identifier of its own, as `swift run` is, imports nothing.
    static func importSettings() {
        guard Bundle.main.bundleIdentifier == current else { return }
        importDefaults(from: UserDefaults.standard.persistentDomain(forName: earlier), into: .standard)
    }

    /// Copies the earlier defaults once, leaving alone whatever this copy has already stored.
    static func importDefaults(from earlier: [String: Any]?, into defaults: UserDefaults) {
        guard !defaults.bool(forKey: importedKey) else { return }
        defaults.set(true, forKey: importedKey)
        for (key, value) in earlier ?? [:] where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
