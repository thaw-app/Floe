//
//  RaycastExport.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import CryptoKit
import Foundation

/// A quicklink as Raycast exports it, before Floe turns it into one of its own.
nonisolated struct RaycastQuicklink: Equatable {
    var name: String
    var link: String
    /// The app the link opens in: its name in a quicklinks export, its path in a backup.
    var openWith: String?
    var iconName: String?

    init(name: String, link: String, openWith: String? = nil, iconName: String? = nil) {
        self.name = name
        self.link = link
        self.openWith = openWith
        self.iconName = iconName
    }
}

/// Reads the quicklinks out of a file Raycast exported.
nonisolated enum RaycastExport {
    enum Reading: Equatable {
        case quicklinks([RaycastQuicklink])
        case needsPassphrase
        case wrongPassphrase
        case notAnExport
    }

    /// The scrypt cost N that Raycast derives a backup's key with.
    static let raycastCost = 16384

    /// Reads a quicklinks export, or a Raycast 2 backup with its passphrase. A backup runs scrypt first: call it off the main actor.
    /// Tests pass a lower cost, since Raycast's takes seconds in a debug build.
    static func read(_ file: Data, passphrase: String?, cost: Int = raycastCost) -> Reading {
        if file.starts(with: Backup.signature) {
            return readBackup(file, passphrase: passphrase, cost: cost)
        }
        guard let entries = try? JSONSerialization.jsonObject(with: file) as? [[String: Any]],
              entries.contains(where: { $0["link"] is String })
        else {
            return .notAnExport
        }
        return .quicklinks(quicklinks(in: entries, apps: nil))
    }

    /// The .rayconfig of Raycast 2: a signature, the length of a gzipped JSON header that holds the IV and salt,
    /// that header, then the gzipped payload sealed with AES-256-GCM under a scrypt key, and the 16-byte tag.
    private enum Backup {
        static let signature = Data("RAYCFG3\n".utf8)
        static let schemaVersion = 3
        static let headerLimit = 1024 * 1024
        static let payloadLimit = 512 * 1024 * 1024
        static let tagLength = 16
    }

    private static func readBackup(_ file: Data, passphrase: String?, cost: Int) -> Reading {
        let bytes = [UInt8](file)
        let lengthStart = Backup.signature.count
        guard bytes.count >= lengthStart + 4 else { return .notAnExport }
        let headerLength = bytes[lengthStart ..< lengthStart + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        let headerStart = lengthStart + 4
        let payloadStart = headerStart + headerLength
        guard headerLength > 0, headerLength <= Backup.headerLimit, payloadStart <= bytes.count,
              let headerJSON = Gzip.decompress(Data(bytes[headerStart ..< payloadStart]), limit: Backup.headerLimit),
              let header = try? JSONDecoder().decode(RaycastBackupHeader.self, from: headerJSON),
              header.schemaVersion == Backup.schemaVersion,
              let iv = Data(hexadecimal: header.encryption.iv), iv.count == 16,
              let salt = Data(hexadecimal: header.encryption.salt), salt.count == 16,
              bytes.count >= payloadStart + Backup.tagLength
        else {
            return .notAnExport
        }
        guard let passphrase, !passphrase.isEmpty else { return .needsPassphrase }
        let tagStart = bytes.count - Backup.tagLength
        guard let key = try? Scrypt.derive(password: Data(passphrase.utf8), salt: salt, cost: cost, blockSize: 8, parallelism: 1, length: 32),
              let box = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: bytes[payloadStart ..< tagStart], tag: bytes[tagStart...]),
              let sealed = try? AES.GCM.open(box, using: SymmetricKey(data: key))
        else {
            return .wrongPassphrase
        }
        guard let payload = Gzip.decompress(sealed, limit: Backup.payloadLimit),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            return .notAnExport
        }
        // Someone who never made a quicklink has a backup without the section.
        let section = object["quicklinks"] as? [String: Any] ?? [:]
        let entries = section["quicklinks"] as? [[String: Any]] ?? []
        // A backup names the app a link opens in by an id into this table, or by its path.
        let apps = (section["openWithPlatforms"] as? [[String: Any]] ?? []).reduce(into: [String: String]()) { table, row in
            if let id = text(row["id"]), let path = text(row["macos"]) { table[id] = path }
        }
        return .quicklinks(quicklinks(in: entries, apps: apps))
    }

    private static func quicklinks(in entries: [[String: Any]], apps: [String: String]?) -> [RaycastQuicklink] {
        entries.compactMap { entry in
            guard let name = text(entry["name"]), let link = text(entry["link"]) else { return nil }
            return RaycastQuicklink(name: name, link: link, openWith: app(text(entry["openWith"]), in: apps), iconName: text(entry["iconName"]))
        }
    }

    /// In a quicklinks export the app is named as it is; in a backup an id that is not a path must be in the table.
    private static func app(_ value: String?, in apps: [String: String]?) -> String? {
        guard let value, let apps else { return value }
        return value.hasPrefix("/") ? value : apps[value]
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string
    }
}

/// The readable start of a Raycast 2 backup: its container version and what its encryption was set up with.
private nonisolated struct RaycastBackupHeader: Decodable {
    struct Encryption: Decodable {
        let iv: String
        let salt: String
    }

    let schemaVersion: Int
    let encryption: Encryption
}
