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

    /// What a sealed file starts with. A plain file from before that happens to start the same fails to open.
    static let marker = Data("FLOESEAL1".utf8)

    static let unavailable = ClipboardSeal(key: nil, isLocked: true)

    /// The app's, from the storage key once the app has turned it on. Read on each use, so a keychain that
    /// gave nothing at launch is asked again.
    static var app: ClipboardSeal {
        switch StorageKey.forApp() {
        case .off: ClipboardSeal(key: nil)
        case let .key(key): ClipboardSeal(key: Data(base64Encoded: key).map { SymmetricKey(data: $0) })
        case .unavailable: .unavailable
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

    /// The file's own bytes. Nil for a sealed one that does not open with this key: never its ciphertext.
    func open(_ data: Data, name: String) -> Data? {
        guard isSealed(data) else { return data }
        guard let key, let box = try? AES.GCM.SealedBox(combined: data.dropFirst(Self.marker.count)) else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: Data(name.utf8))
    }
}
