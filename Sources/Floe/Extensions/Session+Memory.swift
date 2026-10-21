//
//  Session+Memory.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension ExtensionSession {
    /// One extension must not take the Mac's memory: a host holding more than this is stopped.
    static let memoryCeiling: UInt64 = 1 << 30

    /// An unresponsive or errored host can still allocate memory, so an earlier failure does not exempt it.
    func stopsOverCeiling(holding memory: UInt64) -> Bool {
        guard memory > Self.memoryCeiling, !isStopping else { return false }
        failure = SessionFailure(
            kind: .crashed,
            message: String(localized: "The extension used too much memory and was stopped.", bundle: .floe),
            details: String(localized: "It held \(memory / 1_048_576) MB.", bundle: .floe, comment: "The placeholder is a number of megabytes.")
        )
        forceStop()
        onMessage(["type": "crashed"])
        return true
    }

    /// A message too long to keep waiting for is held by Floe, not the host, so the host is stopped for it here.
    func stopsOverLineLimit(holding bytes: Int) {
        guard !isStopping else { return }
        failure = SessionFailure(
            kind: .crashed,
            message: String(localized: "The extension sent a message too large to read and was stopped.", bundle: .floe),
            details: String(localized: "One message ran past \(bytes / 1_048_576) MB.", bundle: .floe, comment: "The placeholder is a number of megabytes.")
        )
        forceStop()
        onMessage(["type": "crashed"])
    }
}
