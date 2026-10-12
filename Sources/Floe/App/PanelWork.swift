//
//  PanelWork.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Synchronization

/// Closing a panel must not cancel a command, paste, or automation request it just started.
/// Only finite user work takes a lease; catalog watchers and search subscriptions do not.
nonisolated enum PanelWork {
    private static let count = Mutex(0)
    static var isBusy: Bool {
        count.withLock { $0 != 0 }
    }

    final class Lease: Sendable {
        fileprivate init() {
            count.withLock { $0 += 1 }
        }

        deinit { count.withLock { $0 -= 1 } }
    }

    static func begin() -> Lease {
        Lease()
    }

    @MainActor
    @discardableResult
    static func perform<T: Sendable>(_ work: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let lease = begin()
        return Task {
            defer { withExtendedLifetime(lease) {} }
            return await work()
        }
    }
}
