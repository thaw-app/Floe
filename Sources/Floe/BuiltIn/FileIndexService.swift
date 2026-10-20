//
//  FileIndexService.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import CoreServices
import FloeRust
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
        /// Starts reporting changes under a folder, from now on or since an earlier event, and returns what stops the reports.
        var watch: @Sendable (String, UInt64?, @escaping @Sendable ([FileIndexChange], UInt64) -> Void) -> (@Sendable () -> Void) = FileIndexEvents.watch
        /// Where the index is kept between launches. Nil keeps it in memory only, and every launch walks the folder.
        var saved: URL?
        /// Off for a copy that reads the saved cache but must leave it alone, as a test's does.
        var writesCache = true
        /// What numbers the folder's events: a saved index is only picked up on the same one.
        var volume: @Sendable (String) -> String? = FileIndexEvents.volume(of:)
        /// The newest event there is, which is where a walk that starts now is safe to be picked up from.
        var currentEvent: @Sendable () -> UInt64 = { FSEventsGetCurrentEventId() }
        /// How long after a change the index is saved, with every change made meanwhile. The saved file is the whole
        /// index, so it is written seldom: a launch replays the events since the save.
        var saveDelay: TimeInterval = 30 * 60
        /// When a file was last opened, for the order of the matches. Nil for one not opened lately.
        var lastUsed: @Sendable (String) -> Date? = RecentFileUse.date(for:)
    }

    static let shared = FileIndexService(environment: Environment(saved: savedFile))

    /// A cache: macOS may clear it, and the next launch then walks the folder again.
    static let savedFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("Floe/FileNames.index")

    /// How deep the first, quick walk goes: Desktop, Documents and Downloads, and two levels inside them.
    static let firstLevels = 3

    /// What goes with a saved index: the event it is good up to, and the volume that numbered it.
    struct Stamp: Codable, Equatable {
        var event: UInt64
        var volume: String
    }

    static func stampFile(for saved: URL) -> URL {
        saved.appendingPathExtension("stamp")
    }

    /// Folders that hold nothing a person looks for by name. Names that start with a dot are left out without being listed.
    static let excludedNames = ["Library", "node_modules", ".git", ".Trash", ".build", "target", "DerivedData", ".cache", "Pods", ".npm", ".cargo", ".rustup"]
    /// Folders that Finder shows as one file: each is one entry, and what is inside is not listed.
    /// A name ending in .noindex is how a folder asks not to be indexed, as build folders do.
    static let packageSuffixes = [".app", ".framework", ".bundle", ".plugin", ".kext", ".xcodeproj", ".xcworkspace", ".xcassets", ".photoslibrary", ".lproj", ".noindex"]

    private struct Running {
        let index: FileIndex
        var root = ""
        var stop: @Sendable () -> Void = { /* Nothing watches the disk until the index starts. */ }
        var isReady = false
        /// The last event the index holds the changes of.
        var event: UInt64 = 0
        /// Changes are waiting for the save that is due.
        var hasUnsavedChanges = false
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

    /// Whether the index is switched on, built or not. Asked as a query is typed: unlike `state`, it measures nothing.
    var isOn: Bool {
        running.withLock { $0 != nil }
    }

    /// What Settings shows. Counting the bytes walks the whole index, so the search asks `isOn` instead.
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
                // Runs after any save already in flight, and before a later start can load the cache.
                work.async { [self] in removeSaved() }
            }
            publish()
        }
    }

    private func start() {
        guard let index = try? FileIndex() else { return }
        running.withLock { running in
            guard running == nil else { return }
            running = Running(index: index)
            work.async { [weak self] in self?.initialize(index) }
        }
        publish()
    }

    /// Runs entirely on the serial worker: even an immediate replay is queued behind loading the index.
    private func initialize(_ index: FileIndex) {
        guard isCurrent(index) else { return }
        publish()
        let root = environment.root()
        let stamp = stamp(for: root)
        let event = stamp?.event ?? environment.currentEvent()
        let stop = environment.watch(root, stamp?.event) { [weak self] changes, event in
            guard let self else { return }
            work.async { self.apply(changes, upTo: event, to: index) }
        }
        let started = running.withLock { running in
            guard running?.index === index else { return false }
            running?.root = root
            running?.stop = stop
            running?.event = event
            return true
        }
        guard started else {
            stop()
            return
        }
        if stamp != nil, let saved = environment.saved, index.load(from: saved, root: root, excludedNames: Self.excludedNames, packageSuffixes: Self.packageSuffixes) {
            setReady(true, for: index)
        } else {
            build(index, root: root)
        }
    }

    /// What was saved with the index, when it is for the volume the folder is on now.
    private func stamp(for root: String) -> Stamp? {
        guard let saved = environment.saved, let data = try? Data(contentsOf: Self.stampFile(for: saved)),
              let stamp = try? JSONDecoder().decode(Stamp.self, from: data), stamp.volume == environment.volume(root)
        else { return nil }
        return stamp
    }

    private func build(_ index: FileIndex, root: String) {
        guard isCurrent(index) else { return }
        // The top folders are read in a few milliseconds and answer searches while the whole walk runs.
        index.build(root: root, excludedNames: Self.excludedNames, packageSuffixes: Self.packageSuffixes, levels: Self.firstLevels)
        setReady(true, for: index)
        guard isCurrent(index) else { return }
        index.build(root: root, excludedNames: Self.excludedNames, packageSuffixes: Self.packageSuffixes)
        publish()
        save(index)
    }

    private func apply(_ changes: [FileIndexChange], upTo event: UInt64, to index: FileIndex) {
        guard isCurrent(index), let root = running.withLock({ $0?.root }) else { return }
        if changes.contains(.everything) {
            setReady(false, for: index)
            build(index, root: root)
        } else {
            for change in changes {
                switch change {
                case let .folder(path): index.rescan(path, recursive: false)
                case let .subtree(path): index.rescan(path, recursive: true)
                case .everything: break
                }
            }
            publish()
        }
        let isFirst = running.withLock { running -> Bool? in
            guard var now = running, now.index === index else { return nil }
            let wasSaved = !now.hasUnsavedChanges
            now.event = max(now.event, event)
            now.hasUnsavedChanges = true
            running = now
            return wasSaved
        }
        guard let isFirst else { return }
        guard environment.saveDelay > 0 else { return save(index) }
        guard isFirst else { return }
        work.asyncAfter(deadline: .now() + environment.saveDelay) { [weak self] in
            self?.save(index)
        }
    }

    /// Saves the changes still waiting, before Floe quits. A walk still under way is not waited out: the next launch
    /// replays what the saved index lacks.
    func flush() {
        let done = DispatchSemaphore(value: 0)
        work.async { [self] in
            if let index = running.withLock({ $0?.hasUnsavedChanges == true ? $0?.index : nil }) {
                save(index)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    /// The index first and its stamp after: a launch that finds a newer index than its stamp reads a few events twice.
    private func save(_ index: FileIndex) {
        guard environment.writesCache, let saved = environment.saved,
              let now = running.withLock({ $0?.index === index ? $0 : nil }),
              let volume = environment.volume(now.root)
        else { return }
        try? FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        running.withLock { $0?.hasUnsavedChanges = false }
        guard index.save(to: saved), let stamp = try? JSONEncoder().encode(Stamp(event: now.event, volume: volume)) else { return }
        try? stamp.write(to: Self.stampFile(for: saved), options: .atomic)
    }

    /// The names of the user's files do not outlive the switch.
    private func removeSaved() {
        guard environment.writesCache, let saved = environment.saved else { return }
        try? FileManager.default.removeItem(at: saved)
        try? FileManager.default.removeItem(at: Self.stampFile(for: saved))
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
