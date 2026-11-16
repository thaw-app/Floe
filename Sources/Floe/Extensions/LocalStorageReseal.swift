//
//  LocalStorageReseal.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
import Foundation
import SQLite3

/// Seals an extension's LocalStorage rows again under another key, in the app, so the runtime is never handed the
/// key they were sealed with. The row layout is the runtime's own (runtime/local-storage.ts) and must stay the same.
nonisolated enum LocalStorageReseal {
    static let prefix = "sealed1:"

    enum Outcome: Equatable, Sendable {
        case done(resealed: Int)
        /// Another process held the file, it has a second name, or SQLite failed otherwise: the rows stay as they
        /// are, to be done later.
        case busy
        /// Not a database: the runtime moves such a file aside, so there is nothing to keep.
        case unreadable
        case missing
    }

    /// SQLite's SQLITE_TRANSIENT, which the C header defines as a cast Swift does not import: SQLite copies the text
    /// before the bind returns, so the Swift string may go away at once.
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    /// The JSON sealed as the runtime seals it, with the item's key bound in. The order is the runtime's, IV then tag
    /// then ciphertext, which is not the order of CryptoKit's combined form.
    static func seal(json: String, itemKey: String, key: SymmetricKey, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> String {
        let box = try AES.GCM.seal(Data(json.utf8), using: key, nonce: nonce, authenticating: Data(itemKey.utf8))
        return prefix + (Data(box.nonce) + box.tag + box.ciphertext).base64EncodedString()
    }

    /// The JSON a sealed row holds, or nil when it is not sealed, damaged, or sealed under another key.
    static func open(_ stored: String, itemKey: String, key: SymmetricKey) -> String? {
        guard stored.hasPrefix(prefix), let bytes = Data(base64Encoded: String(stored.dropFirst(prefix.count))), bytes.count >= 28,
              let nonce = try? AES.GCM.Nonce(data: bytes.prefix(12)),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: bytes.dropFirst(28), tag: bytes.dropFirst(12).prefix(16)),
              let json = try? AES.GCM.open(box, using: key, authenticating: Data(itemKey.utf8))
        else { return nil }
        return String(data: json, encoding: .utf8)
    }

    /// Seals every row that opens under the old key, and not already under the new one, under the new key. Rows that
    /// open under neither are left as they are. The file is never created, and the busy wait is the runtime's.
    static func reseal(file: URL, from legacy: SymmetricKey, to own: SymmetricKey, busyWait: Int32 = 5000) -> Outcome {
        guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
        var handle: OpaquePointer?
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database = handle else {
            return failure(sqlite3_errcode(handle))
        }
        sqlite3_busy_timeout(database, busyWait)
        // The old ciphertext is overwritten where it was, not left in free pages.
        sqlite3_exec(database, "PRAGMA secure_delete = ON", nil, nil, nil)
        let began = sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil)
        guard began == SQLITE_OK else { return failure(began) }
        guard isOwnFile(file) else {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            return .busy
        }
        guard let rows = sealedRows(in: database) else {
            let code = sqlite3_errcode(database)
            let missingTable = String(cString: sqlite3_errmsg(database)).contains("no such table")
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            return missingTable ? .done(resealed: 0) : failure(code)
        }
        var resealed = 0
        for row in rows {
            guard let value = resealedValue(row, from: legacy, to: own) else { continue }
            guard update(row, to: value, in: database) else {
                let code = sqlite3_errcode(database)
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                return failure(code)
            }
            resealed += 1
        }
        let committed = sqlite3_exec(database, "COMMIT", nil, nil, nil)
        guard committed == SQLITE_OK else {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            return failure(committed)
        }
        if resealed > 0 {
            // Rewrites the file, so no page keeps a row as it was.
            sqlite3_exec(database, "VACUUM", nil, nil, nil)
        }
        return .done(resealed: resealed)
    }

    private struct Row {
        let key: String
        let value: String
    }

    /// What a failed SQLite call means here. Anything but a file that is not a database keeps the rows for a later try.
    /// Whether the path leads to a file of its own folder: a regular file with one name, in the folder the path names
    /// and not one a link leads to. A link to another extension's file or folder would have that extension's rows
    /// sealed with this one's key. Checked once SQLite holds the file, so a link made earlier is caught.
    private static func isOwnFile(_ file: URL) -> Bool {
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { return false }
        let folder = file.deletingLastPathComponent()
        guard let real = realPath(file), let data = realPath(folder.deletingLastPathComponent()) else { return false }
        return real == "\(data)/\(folder.lastPathComponent)/\(file.lastPathComponent)"
    }

    private static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func failure(_ code: Int32) -> Outcome {
        switch code & 0xFF {
        case SQLITE_NOTADB, SQLITE_CORRUPT: .unreadable
        default: .busy
        }
    }

    /// Every sealed row, read before any is changed. Nil when SQLite failed.
    private static func sealedRows(in database: OpaquePointer) -> [Row]? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT key, value FROM items WHERE value LIKE 'sealed1:%'", -1, &statement, nil) == SQLITE_OK else { return nil }
        var rows: [Row] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let key = text(statement, column: 0), let value = text(statement, column: 1) else { continue }
                rows.append(Row(key: key, value: value))
            case SQLITE_DONE:
                return rows
            default:
                return nil
            }
        }
    }

    /// A column's text by its length, so a key with a NUL inside is read whole, as the runtime wrote it.
    private static func text(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8)
    }

    /// Binds the text by its length, for the same reason.
    private static func bind(_ text: String, at index: Int32, in statement: OpaquePointer?) {
        let bytes = text.utf8CString
        _ = bytes.withUnsafeBufferPointer { sqlite3_bind_text(statement, index, $0.baseAddress, Int32($0.count - 1), transient) }
    }

    /// The row sealed under the new key, when it opens under the old one and not already under the new one.
    private static func resealedValue(_ row: Row, from legacy: SymmetricKey, to own: SymmetricKey) -> String? {
        guard open(row.value, itemKey: row.key, key: own) == nil, let json = open(row.value, itemKey: row.key, key: legacy) else { return nil }
        return try? seal(json: json, itemKey: row.key, key: own)
    }

    /// Changes the row only while it still holds what was read.
    private static func update(_ row: Row, to value: String, in database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "UPDATE items SET value = ? WHERE key = ? AND value = ?", -1, &statement, nil) == SQLITE_OK else { return false }
        bind(value, at: 1, in: statement)
        bind(row.key, at: 2, in: statement)
        bind(row.value, at: 3, in: statement)
        return sqlite3_step(statement) == SQLITE_DONE
    }
}
