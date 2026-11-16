//
//  ClipboardSeal.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
import Foundation

/// Seals the clipboard folder's files with the storage key, AES-GCM with the file's name bound in, so a file
/// another program reads is no use to it. Without a key, files stay plain.
nonisolated struct ClipboardSeal: Sendable {
    let key: SymmetricKey?
    /// True when there should be a key and the keychain gave none: nothing is written until it does.
    var isLocked = false
    /// The key from before, read only, until the folder has been sealed again with the new one.
    var legacy: SymmetricKey?

    /// What a sealed file starts with. A plain file from before that happens to start the same fails to open.
    static let marker = Data("FLOESEAL1".utf8)

    static let unavailable = ClipboardSeal(key: nil, isLocked: true)

    /// The app's, from the storage key once the app has turned it on. Read on each use, so a keychain that
    /// gave nothing at launch is asked again.
    static var app: ClipboardSeal {
        let legacy = StorageKey.legacyForApp()
        // An old key that could not be read leaves the history locked, so what it sealed is not written over.
        if legacy == .unreadable {
            return .unavailable
        }
        switch StorageKey.forApp() {
        case .off:
            return ClipboardSeal(key: nil)
        case let .key(key):
            var seal = ClipboardSeal(key: StorageKey.symmetricKey(key))
            if case let .key(old) = legacy {
                seal.legacy = StorageKey.symmetricKey(old)
            }
            return seal
        case .unavailable:
            return .unavailable
        }
    }

    enum Failure: Error {
        case locked
    }

    func isSealed(_ data: Data) -> Bool {
        data.starts(with: Self.marker)
    }

    func seal(_ data: Data, name: String) throws -> Data {
        if isLocked {
            throw Failure.locked
        }
        guard let key else { return data }
        guard let combined = try AES.GCM.seal(data, using: key, authenticating: Data(name.utf8)).combined else {
            throw CryptoKitError.incorrectParameterSize
        }
        return Self.marker + combined
    }

    /// The file's own bytes. Nil for a sealed one that opens with neither key: never its ciphertext.
    func open(_ data: Data, name: String) -> Data? {
        guard isSealed(data) else { return data }
        guard let box = try? AES.GCM.SealedBox(combined: data.dropFirst(Self.marker.count)) else { return nil }
        for key in [key, legacy].compactMap(\.self) {
            if let opened = try? AES.GCM.open(box, using: key, authenticating: Data(name.utf8)) {
                return opened
            }
        }
        return nil
    }

    /// Seals again with the new key each file in the folder that opens only with the old one. False while the old key
    /// may still be needed: the folder is locked, or a file could not be written.
    func resealLegacyFiles(in directory: URL) -> Bool {
        guard !isLocked else { return false }
        guard let legacy else { return true }
        // Without the new key the files would be written plainly.
        guard key != nil else { return false }
        let current = ClipboardSeal(key: key)
        let old = ClipboardSeal(key: legacy)
        var done = true
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? [] {
            let name = url.lastPathComponent
            // A link is not followed, as when plain files are sealed.
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: url), current.isSealed(data), current.open(data, name: name) == nil,
                  let plain = old.open(data, name: name)
            else { continue }
            guard let sealed = try? current.seal(plain, name: name), (try? sealed.write(to: url, options: .atomic)) != nil else {
                done = false
                continue
            }
            PrivateStorage.restrict(url, to: 0o600)
        }
        return done
    }
}
