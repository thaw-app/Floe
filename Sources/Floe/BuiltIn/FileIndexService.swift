//
//  FileIndexService.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import FendCore
import Foundation
import Synchronization
import UniformTypeIdentifiers

/// The names of the files in the home folder, held in memory so a file search is answered as it is typed.
/// Off until its switch in Settings, Privacy: walking the home folder makes macOS ask about the folders it guards.
final nonisolated class FileIndexService: Sendable {
    enum State: Equatable, Sendable {
        case off
        case building
        case ready(names: Int, bytes: Int)
    }

    /// What reaches the disk and the file system's events. Tests pass a folder and events of their own.
    struct Environment: Sendable {
        /// The folder to index, as file system events name it.
        var root: @Sendable () -> String = { DirectoryWatcher.real(NSHomeDirectory()) }
        /// Starts reporting changes under a folder, and returns what stops the reports.
        var watch: @Sendable (String, @escaping @Sendable ([FileIndexChange]) -> Void) -> (@Sendable () -> Void) = FileIndexEvents.watch
        /// When a file was last opened, for the order of the matches. Nil for one not opened lately.
        var lastUsed: @Sendable (String) -> Date? = RecentFileUse.date(for:)
    }

    static let shared = FileIndexService()

    /// Folders that hold nothing a person looks for by name. Names that start with a dot are left out without being listed.
    static let excludedNames = ["Library", "node_modules", ".git", ".Trash", ".build", "target", "DerivedData", ".cache", "Pods", ".npm", ".cargo", ".rustup"]
    /// Folders that Finder shows as one file: each is one entry, and what is inside is not listed.
    /// A name ending in .noindex is how a folder asks not to be indexed, as build folders do.
    static let packageSuffixes = [".app", ".framework", ".bundle", ".plugin", ".kext", ".xcodeproj", ".xcworkspace", ".xcassets", ".photoslibrary", ".lproj", ".noindex"]

    private struct Running {
        let index: FileIndex
        let root: String
        let stop: @Sendable () -> Void
        var isReady = false
    }

    private let environment: Environment
    private let running = Mutex<Running?>(nil)
    private let observer = Mutex<(@MainActor @Sendable (State) -> Void)?>(nil)
    private let published = Mutex<State?>(nil)
    /// The walk and every rescan, one after another and below whatever the user is doing.
    private let work = DispatchQueue(label: "floe.file-index", qos: .utility)

    init(environment: Environment = Environment()) {
        self.environment = environment
    }

    deinit {
        running.withLock { $0?.stop() }
    }

    var state: State {
        running.withLock { running in
            guard let running else { return .off }
            return running.isReady ? .ready(names: running.index.count, bytes: running.index.byteSize) : .building
        }
    }

    /// Told each new state on the main thread, starting with the current one.
    func observe(_ observer: @escaping @MainActor @Sendable (State) -> Void) {
        self.observer.withLock { $0 = observer }
        published.withLock { $0 = nil }
        publish()
    }

    /// On starts the walk and the watching; off frees the index and stops the events.
    func set(on isOn: Bool) {
        if isOn {
            start()
        } else {
            running.withLock { running in
                running?.stop()
                running = nil
            }
            publish()
        }
    }

    private func start() {
        guard let index = try? FileIndex() else { return }
        let root = environment.root()
        let started = running.withLock { running in
            guard running == nil else { return false }
            // Watching starts before the walk, so what changes during it is read again afterwards.
            let stop = environment.watch(root) { [weak self] changes in
                guard let self else { return }
                work.async { self.apply(changes, to: index) }
            }
            running = Running(index: index, root: root, stop: stop)
            return true
        }
        guard started else { return }
        publish()
        work.async { [weak self] in self?.build(index, root: root) }
    }

    private func build(_ index: FileIndex, root: String) {
        guard isCurrent(index) else { return }
        index.build(root: root, excludedNames: Self.excludedNames, packageSuffixes: Self.packageSuffixes)
        setReady(true, for: index)
    }

    private func apply(_ changes: [FileIndexChange], to index: FileIndex) {
        guard isCurrent(index), let root = running.withLock({ $0?.root }) else { return }
        if changes.contains(.everything) {
            setReady(false, for: index)
            build(index, root: root)
            return
        }
        for change in changes {
            switch change {
            case let .folder(path): index.rescan(path, recursive: false)
            case let .subtree(path): index.rescan(path, recursive: true)
            case .everything: break
            }
        }
        publish()
    }

    /// False once the switch went off, or went off and on again, since the work was queued.
    private func isCurrent(_ index: FileIndex) -> Bool {
        running.withLock { $0?.index === index }
    }

    private func setReady(_ isReady: Bool, for index: FileIndex) {
        running.withLock { running in
            if running?.index === index {
                running?.isReady = isReady
            }
        }
        publish()
    }

    private func publish() {
        let state = state
        let isNew = published.withLock { published in
            defer { published = state }
            return published != state
        }
        guard isNew, let observer = observer.withLock({ $0 }) else { return }
        DispatchQueue.main.async { observer(state) }
    }

    /// Returns once the walk and every change handed over so far are in the index.
    func settled() async {
        await withCheckedContinuation { continuation in
            work.async { continuation.resume() }
        }
    }

    /// The files whose names match, best first; nil while there is no finished index to ask.
    func files(matching query: String, limit: Int = 50) -> [FileResult]? {
        guard let index = running.withLock({ $0?.isReady == true ? $0?.index : nil }) else { return nil }
        let home = NSHomeDirectory()
        // Asked for more than is shown, since the apps among the hits are dropped.
        let ranked = Self.ranked(index.search(query, limit: limit * 2), lastUsed: environment.lastUsed)
        return Array(ranked.lazy.compactMap { Self.result(for: $0.hit, home: home, lastUsed: $0.lastUsed) }.prefix(limit))
    }

    /// The hits in the order shown. One opened today gains a quarter of its score, and the gain fades to nothing over thirty days.
    static func ranked(_ hits: [FileIndex.Hit], lastUsed: (String) -> Date?, now: Date = Date()) -> [(hit: FileIndex.Hit, lastUsed: Date?)] {
        let scored = hits.enumerated().map { place, hit in
            let used = lastUsed(hit.path)
            let age = used.map { max(0, now.timeIntervalSince($0)) } ?? RecentFileUse.window
            let weight = max(0, 1 - age / RecentFileUse.window)
            return (place: place, hit: hit, lastUsed: used, score: Double(hit.score) * (1 + 0.25 * weight))
        }
        // Equal scores keep the index's own order: shallower paths, then shorter names.
        return scored.sorted { ($0.score, $1.place) > ($1.score, $0.place) }.map { ($0.hit, $0.lastUsed) }
    }

    /// A hit as the row the file search shows, or nil for what that search leaves out: apps and anything in a Library.
    static func result(for hit: FileIndex.Hit, home: String, lastUsed: Date? = nil) -> FileResult? {
        let url = URL(fileURLWithPath: hit.path, isDirectory: hit.isFolder)
        let name = url.lastPathComponent
        // Apps already have their own scope.
        guard !hit.path.contains("/Library/"), !name.hasSuffix(".app") else { return nil }
        let folder = url.deletingLastPathComponent().path
        let type = url.pathExtension.isEmpty ? nil : UTType(filenameExtension: url.pathExtension)
        return FileResult(
            url: url,
            name: name,
            displayPath: folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder,
            contentType: type?.identifier ?? (hit.isFolder ? UTType.folder.identifier : nil),
            lastUsed: lastUsed,
            matched: hit.matched
        )
    }
}

nonisolated extension FileIndexService.State {
    /// What the Privacy page shows under the switch; nil when there is nothing to say.
    var line: String? {
        switch self {
        case .off: nil
        case .building: String(localized: "Reading the names of your files…", bundle: .floe)
        case let .ready(names, bytes):
            String(
                localized: "\(names) names, \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))",
                bundle: .floe,
                comment: "How many file names Floe holds and the memory they take, such as “203,000 names, 8 MB”."
            )
        }
    }

    /// The state as one word and two numbers, for the message that tells the settings process.
    var text: String {
        switch self {
        case .off: "off"
        case .building: "building"
        case let .ready(names, bytes): "ready \(names) \(bytes)"
        }
    }

    init?(text: String) {
        let words = text.split(separator: " ")
        switch (words.first, words.count) {
        case ("off", 1): self = .off
        case ("building", 1): self = .building
        case ("ready", 3):
            guard let names = Int(words[1]), let bytes = Int(words[2]), names >= 0, bytes >= 0 else { return nil }
            self = .ready(names: names, bytes: bytes)
        default: return nil
        }
    }
}

/// In the settings process, which holds no index: what the launcher last said about its own.
final class FileIndexStatus: ObservableObject {
    static let shared = FileIndexStatus()

    @Published var state: FileIndexService.State?
}
