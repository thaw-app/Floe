//
//  SettingsTransfer.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Floe's settings in one file, to move them to another Mac or keep a copy. Extension preferences
/// come along, but passwords never do: only their names, so an import can say which to enter again.
enum SettingsTransfer {
    static let version = 1

    struct Archive {
        var settings: Data
        /// Plain preference values by extension name, then storage key.
        var preferences: [String: [String: Any]]
        /// Password preference keys by extension name, without their values.
        var secretKeys: [String: [String]]
    }

    struct Summary: Equatable {
        var aliases = 0
        var hotkeys = 0
        var favorites = 0
        var extensions = 0
        /// "extension: key" for each password that has to be entered again.
        var missingSecrets: [String] = []
    }

    enum TransferError: LocalizedError, Equatable {
        case notAnExport
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notAnExport: String(localized: "This file isn't a Floe settings export.", bundle: .floe)
            case .newerVersion: String(localized: "This file was exported by a newer version of Floe.", bundle: .floe)
            }
        }
    }

    static func encode(_ archive: Archive, exportedAt: Date = Date()) throws -> Data {
        let settings = try JSONSerialization.jsonObject(with: archive.settings)
        let object: [String: Any] = [
            "version": version,
            "exportedAt": ISO8601DateFormatter().string(from: exportedAt),
            "settings": settings,
            "extensionPreferences": archive.preferences,
            "secretKeys": archive.secretKeys,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func decode(_ data: Data) throws -> Archive {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileVersion = object["version"] as? Int,
              let settings = object["settings"] as? [String: Any]
        else { throw TransferError.notAnExport }
        guard fileVersion <= version else { throw TransferError.newerVersion(fileVersion) }
        return try Archive(
            settings: JSONSerialization.data(withJSONObject: settings),
            preferences: object["extensionPreferences"] as? [String: [String: Any]] ?? [:],
            // Optional, so files written before secret keys were recorded still load.
            secretKeys: object["secretKeys"] as? [String: [String]] ?? [:]
        )
    }

    /// Imported settings with this Mac's consent in place of the file's, as SettingsSync.thisMacOnly says for each
    /// setting. A file can come from anyone. A file that is not settings is handed on as it is, to be refused.
    static func keepingConsent(_ file: Data, of here: AppSettings) -> Data {
        guard var theirs = (try? JSONSerialization.jsonObject(with: file)) as? [String: Any] else { return file }
        // Exporting saves first. With no edit waiting that save changes nothing, so it stays quiet: the other process
        // hears of the import once, from its own save.
        let notify = here.onSaved
        if !here.hasUnsavedChanges {
            here.onSaved = nil
        }
        let exported = try? here.exportedJSON()
        here.onSaved = notify
        guard let mine = exported.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else { return file }
        for (key, local) in SettingsSync.thisMacOnly {
            theirs[key] = local.onImport.value(mine: mine[key], theirs: theirs[key])
        }
        // Only the shell prefix is the file's, as with sync. The rest is this Mac's, written out in full: a file without
        // it, or with a value that does not read, would get defaults that run commands.
        let prefix = ((theirs["shell"] as? [String: Any])?["prefix"] as? String).flatMap(CommandPrefix.init) ?? here.shell.prefix
        theirs["shell"] = ["runs": here.shell.runs, "prefix": prefix.rawValue, "recognizes": here.shell.recognizes, "suggests": here.shell.suggests]
        return (try? JSONSerialization.data(withJSONObject: theirs)) ?? file
    }

    /// What an import brought in, for the message shown afterwards.
    static func summary(of archive: Archive, hasSecret: (String, String) -> Bool) -> Summary {
        let settings = (try? JSONSerialization.jsonObject(with: archive.settings) as? [String: Any]) ?? [:]
        let missing = archive.secretKeys.sorted { $0.key < $1.key }.flatMap { name, keys in
            keys.sorted().filter { !hasSecret(name, $0) }.map { "\(name): \($0)" }
        }
        return Summary(
            aliases: (settings["aliases"] as? [String: Any])?.count ?? 0,
            hotkeys: ((settings["commandHotkeys"] as? [String: Any])?.count ?? 0) + (settings["toggleHotkey"] is [String: Any] ? 1 : 0),
            favorites: (settings["favorites"] as? [Any])?.count ?? 0,
            extensions: archive.preferences.count,
            missingSecrets: missing
        )
    }
}
