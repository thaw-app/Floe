//
//  CommandSubtitles.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The subtitles commands set with `updateCommandMetadata`, by command id, kept until the command clears its own.
/// In the defaults, so the panel's process reads what a background run in the resident wrote.
nonisolated enum CommandSubtitles {
    private static let key = "commandSubtitles"

    static func subtitle(for id: String, in defaults: UserDefaults = .standard) -> String? {
        (defaults.dictionary(forKey: key) as? [String: String])?[id]
    }

    /// Nil or empty clears it, and the manifest's subtitle shows again.
    static func set(_ subtitle: String?, for id: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        all[id] = subtitle.flatMap { $0.isEmpty ? nil : $0 }
        defaults.set(all, forKey: key)
    }
}

extension ExtensionSession {
    /// Takes `commandMetadata` from `updateCommandMetadata`; false for any other message.
    func storedSubtitle(_ fields: [String: Any]) -> Bool {
        guard fields["type"] as? String == "commandMetadata" else { return false }
        CommandSubtitles.set(fields["subtitle"] as? String, for: command.id)
        return true
    }
}
