//
//  StorageMigration.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
import Foundation
import Synchronization

/// Moves what the old storage key sealed to the new keys, then removes the old key. The old key was handed to every
/// extension, so data sealed with it is only safe once nothing sealed with it is left and the key itself is gone.
/// Until an extension's file is done, its LocalStorage is locked: it reads what opens and saves nothing.
nonisolated final class StorageMigration: Sendable {
    struct StorageFile: Sendable, Equatable {
        let name: String
        let file: URL
    }

    struct Environment: Sendable {
        var legacy: @Sendable () -> StorageKey.Legacy
        var root: @Sendable () -> StorageKey.Access
        /// Nil when the data folder could not be read.
        var storageFiles: @Sendable () -> [StorageFile]?
        var reseal: @Sendable (_ file: URL, _ from: SymmetricKey, _ to: SymmetricKey) -> LocalStorageReseal.Outcome
        var retire: @Sendable () -> Void

        static let app = Environment(
            legacy: { StorageKey.legacyForApp() },
            root: { StorageKey.forApp() },
            storageFiles: { StorageMigration.storageFiles(in: Paths.data) },
            reseal: { LocalStorageReseal.reseal(file: $0, from: $1, to: $2) },
            retire: {
                StorageKey.retireLegacy()
                Log.app.notice("The old storage key was removed: everything it sealed is sealed again")
            }
        )
    }

    private struct State {
        var legacy: StorageKey.Legacy?
        var started = false
        var finished = false
        /// No file was done, because the new storage key or the data folder could not be read: every extension stays
        /// locked this launch.
        var blocked = false
        /// Extensions whose file another process held, by ExtensionCommand.folderKey.
        var locked: Set<String> = []
        var clipboard: Bool?
        var retired = false
    }

    static let shared = StorageMigration(environment: .app)

    private let environment: Environment
    private let state = Mutex(State())

    init(environment: Environment) {
        self.environment = environment
    }

    /// The old key, asked of the keychain once.
    private func legacy() -> StorageKey.Legacy {
        if let known = state.withLock({ $0.legacy }) {
            return known
        }
        let asked = environment.legacy()
        return state.withLock { state in
            if let known = state.legacy {
                return known
            }
            state.legacy = asked
            return asked
        }
    }

    /// Starts the move on a queue of its own: it blocks on the keychain and SQLite, which must not hold one of Swift's
    /// few shared threads. Only the launcher's process calls this.
    func begin() {
        let starts = state.withLock { state in
            guard !state.started else { return false }
            state.started = true
            return true
        }
        if starts {
            DispatchQueue.global(qos: .utility).async { [self] in run() }
        }
    }

    func run() {
        guard case let .key(old) = legacy(), let oldKey = StorageKey.symmetricKey(old) else {
            state.withLock { $0.finished = true }
            return
        }
        guard case let .key(root) = environment.root(), let files = environment.storageFiles() else {
            state.withLock {
                $0.blocked = true
                $0.finished = true
            }
            return
        }
        var locked: Set<String> = []
        for storage in files {
            let name = ExtensionCommand.folderKey(storage.name)
            guard let own = StorageKey.extensionKey(root: root, name: storage.name).flatMap(StorageKey.symmetricKey) else {
                locked.insert(name)
                continue
            }
            if environment.reseal(storage.file, oldKey, own) == .busy {
                locked.insert(name)
            }
        }
        state.withLock {
            $0.locked = locked
            $0.finished = true
        }
        retireWhenDone()
    }

    /// The clipboard folder's answer: true once nothing in it is sealed with the old key.
    func clipboardSettled(_ done: Bool) {
        state.withLock { $0.clipboard = done }
        retireWhenDone()
    }

    /// The old key is removed once, when every file and the clipboard folder are done.
    private func retireWhenDone() {
        let retires = state.withLock { state in
            guard case .key = state.legacy, state.finished, !state.blocked, state.locked.isEmpty, state.clipboard == true, !state.retired else {
                return false
            }
            state.retired = true
            return true
        }
        if retires {
            environment.retire()
        }
    }

    /// Whether an extension may have its own key now. While its file still holds rows sealed with the old key, a key
    /// would let it write over them, so it gets none and its storage stays locked.
    func allows(_ name: String) -> Bool {
        switch legacy() {
        case .none: true
        case .unreadable: false
        case .key: state.withLock { $0.retired || ($0.finished && !$0.blocked && !$0.locked.contains(ExtensionCommand.folderKey(name))) }
        }
    }

    /// Waits for the move, up to the limit. Polled, because waiting on the task's value cannot be cut short. A waiter
    /// that is cancelled, as when its command stops, returns at once instead of spinning until the limit.
    func settled(within limit: Duration) async {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while state.withLock({ $0.started && !$0.finished }), clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return
            }
        }
    }

    /// Each extension's LocalStorage file under the data folder, named by its folder. Links are skipped, so one
    /// cannot make the app write somewhere else. Nil when the folder or one in it could not be read: a file missed
    /// would keep rows only the old key opens.
    static func storageFiles(in data: URL) -> [StorageFile]? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let folders: [URL]
        do {
            folders = try FileManager.default.contentsOfDirectory(at: data, includingPropertiesForKeys: Array(keys))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            return nil
        }
        var files: [StorageFile] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? folder.resourceValues(forKeys: keys) else { return nil }
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let file = folder.appendingPathComponent("local-storage.sqlite")
            do {
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                continue
            } catch {
                return nil
            }
            files.append(StorageFile(name: folder.lastPathComponent, file: file))
        }
        return files
    }
}
