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

    /// Imported settings with this Mac's consent in place of the file's. A file can come from anyone, so it never
    /// lends a sign-in, switches on a search source, the file index, iCloud sync or running shell commands, allows a
    /// download, or loosens the promise to keep AI on this Mac, which it may only tighten. A file that is not settings is
    /// handed on as it is, to be refused.
    static func keepingConsent(_ file: Data, of here: AppSettings) -> Data {
        guard var theirs = (try? JSONSerialization.jsonObject(with: file)) as? [String: Any] else { return file }
        theirs["lentSignIns"] = here.lentSignIns.sorted()
        theirs["searchSources"] = here.searchSources.sorted()
        theirs["indexesFileNames"] = here.indexesFileNames
        theirs["fetchesExchangeRates"] = here.fetchesExchangeRates
        theirs["syncsWithICloud"] = here.syncsWithICloud
        // A file without shell settings would get the defaults, which run commands.
        var shell = theirs["shell"] as? [String: Any] ?? [:]
        shell["runs"] = here.shell.runs
        theirs["shell"] = shell
        theirs["aiOnThisMacOnly"] = here.aiOnThisMacOnly || theirs["aiOnThisMacOnly"] as? Bool == true
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
