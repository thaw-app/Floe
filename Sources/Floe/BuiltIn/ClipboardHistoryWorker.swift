//
//  ClipboardHistoryWorker.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Synchronization

/// The clipboard folder's file operations, so a test can count them, hold one back or make one fail.
nonisolated struct ClipboardFiles: Sendable {
    static let historyName = "history.json"

    var directory: URL
    /// Every file in the folder with its size: the one read of the directory, made at load.
    var sizes: @Sendable () -> [String: Int]
    var read: @Sendable (_ name: String) -> Data?
    var write: @Sendable (_ data: Data, _ name: String, _ atomically: Bool) throws -> Void
    var remove: @Sendable (_ name: String) -> Void

    /// The real folder: private to the user, 0700 with 0600 files.
    static func onDisk(_ directory: URL) -> ClipboardFiles {
        @Sendable func ensureDirectory() {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        return ClipboardFiles(
            directory: directory,
            sizes: {
                ensureDirectory()
                let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                return Dictionary(
                    items.map { ($0.lastPathComponent, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) },
                    uniquingKeysWith: { first, _ in first }
                )
            },
            read: { try? Data(contentsOf: directory.appendingPathComponent($0)) },
            write: { data, name, atomically in
                ensureDirectory()
                let url = directory.appendingPathComponent(name)
                try data.write(to: url, options: atomically ? .atomic : [])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            },
            remove: { try? FileManager.default.removeItem(at: directory.appendingPathComponent($0)) }
        )
    }
}

/// The bytes the clipboard folder holds, kept as files come and go instead of measured again.
nonisolated struct ClipboardByteLedger {
    private(set) var total = 0
    private var sizes: [String: Int] = [:]

    init(sizes: [String: Int] = [:]) {
        self.sizes = sizes
        total = sizes.values.reduce(0, +)
    }

    mutating func set(_ name: String, bytes: Int) {
        total += bytes - (sizes.updateValue(bytes, forKey: name) ?? 0)
    }

    mutating func remove(_ name: String) {
        total -= sizes.removeValue(forKey: name) ?? 0
    }
}

/// Does the clipboard history's slow work off the main thread, one job at a time in the order asked.
/// The store decides; what this produces waits in `takeEvents()` for it, in the same order.
final nonisolated class ClipboardHistoryWorker: Sendable {
    enum Event: Sendable {
        case loaded([ClipboardEntry], sizes: [String: Int])
        case prepared(ClipboardEntry, sizes: [String: Int], epoch: Int)
        /// The list as written.
        case saved(bytes: Int, [ClipboardEntry])
        /// Formatted copies that could not be written, which the list must stop naming.
        case unstored([String])
    }

    private enum Job: Sendable {
        case load
        case prepare(ClipboardCapture, epoch: Int)
        case store([String: Data])
        case remove([String])
        case save
        /// A save once the worker takes it, holding the newest list.
        case write([ClipboardEntry])
        case signal(DispatchSemaphore)
    }

    /// The jobs not started yet, in the order asked, and the original image data they hold.
    private struct Queue {
        var jobs: [Job] = []
        var imageBytes = 0
        /// The newest list waiting to be written; a burst of changes becomes one write.
        var unsaved: [ClipboardEntry]?

        mutating func next() -> Job? {
            guard !jobs.isEmpty else { return nil }
            switch jobs.removeFirst() {
            case let .prepare(capture, epoch):
                imageBytes -= capture.imageBytes
                return .prepare(capture, epoch: epoch)
            case .save:
                // Taken with its job, so a list changed from here on is written by a save queued after it.
                return unsaved.take().map(Job.write) ?? .save
            case let job:
                return job
            }
        }

        /// Over budget, the oldest waiting images go and the newest copy always stays, even alone over it.
        /// One copied with text stays in its place as that text; nothing kept changes place.
        mutating func shed(to budget: Int) {
            var index = 0
            while imageBytes > budget, index < jobs.count - 1 {
                guard case let .prepare(capture, epoch) = jobs[index], case let .image(data, fallbackText) = capture.content else {
                    index += 1
                    continue
                }
                imageBytes -= data.count
                if let fallbackText, !fallbackText.isEmpty {
                    var kept = capture
                    kept.content = .text(fallbackText)
                    jobs[index] = .prepare(kept, epoch: epoch)
                    index += 1
                } else {
                    jobs.remove(at: index)
                }
            }
        }
    }

    /// What the worker's task and its owner both reach.
    private final class Shared: Sendable {
        let queue = Mutex(Queue())
        let events = Mutex<[Event]>([])
    }

    private let files: ClipboardFiles
    private let maxQueuedBytes: Int
    private let storedPNG: @Sendable (Data) -> Data?
    /// Its own thread, not the shared task pool: a wait for the worker can never be a wait for a free thread.
    private let runner = DispatchQueue(label: "org.thaw.floe.clipboard-worker", qos: .utility)
    private let shared = Shared()
    private let wake: AsyncStream<Void>.Continuation

    /// Yields whenever events are waiting, and ends with the worker.
    let wakes: AsyncStream<Void>

    /// The original image data held by copies that are waiting and not yet started.
    var queuedBytes: Int {
        shared.queue.withLock { $0.imageBytes }
    }

    init(files: ClipboardFiles, maxQueuedBytes: Int, storedPNG: @escaping @Sendable (Data) -> Data?) {
        self.files = files
        self.maxQueuedBytes = maxQueuedBytes
        self.storedPNG = storedPNG
        (wakes, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        wake.finish()
    }

    /// Runs the waiting jobs in order. The jobs wait in shared.queue, where one can be dropped before it starts.
    private func tick() {
        runner.async { [files, storedPNG, shared, wake] in
            while let job = shared.queue.withLock({ $0.next() }) {
                // The pool frees what decoding an image leaves behind before the next job starts.
                let events = autoreleasepool { Self.run(job, files: files, storedPNG: storedPNG) }
                guard !events.isEmpty else { continue }
                shared.events.withLock { $0 += events }
                wake.yield()
            }
        }
    }

    private func enqueue(_ job: Job) {
        shared.queue.withLock { $0.jobs.append(job) }
        tick()
    }

    /// Reads the saved list, once for any number of asks still waiting.
    func load() {
        shared.queue.withLock { queue in
            let waiting = queue.jobs.firstIndex { job in
                if case .load = job {
                    true
                } else {
                    false
                }
            }
            if waiting == nil {
                queue.jobs.append(.load)
            }
        }
        tick()
    }

    /// Queues a copy, making room for it first: this never waits for the worker.
    func prepare(_ capture: ClipboardCapture, epoch: Int) {
        shared.queue.withLock { queue in
            queue.jobs.append(.prepare(capture, epoch: epoch))
            queue.imageBytes += capture.imageBytes
            // Only a new image makes room, so text arriving later never costs the image before it.
            if capture.imageBytes > 0 {
                queue.shed(to: maxQueuedBytes)
            }
        }
        tick()
    }

    /// Drops every copy not started yet, so none is decoded or written and its data is freed now.
    func discardQueuedCopies() {
        shared.queue.withLock { queue in
            queue.jobs.removeAll { job in
                if case .prepare = job {
                    true
                } else {
                    false
                }
            }
            queue.imageBytes = 0
        }
    }

    /// Writes the formatted copies of an entry already in the list, ahead of a waiting save,
    /// so the saved list never names a file that is not there yet.
    func store(_ files: [String: Data]) {
        guard !files.isEmpty else { return }
        shared.queue.withLock { queue in
            let save = queue.jobs.firstIndex { job in
                if case .save = job {
                    true
                } else {
                    false
                }
            }
            queue.jobs.insert(.store(files), at: save ?? queue.jobs.endIndex)
        }
        tick()
    }

    func remove(_ names: [String]) {
        if !names.isEmpty {
            enqueue(.remove(names))
        }
    }

    func save(_ entries: [ClipboardEntry]) {
        shared.queue.withLock { queue in
            if queue.unsaved == nil {
                queue.jobs.append(.save)
            }
            queue.unsaved = entries
        }
        tick()
    }

    /// Blocks until every job asked for so far has run, or the time is up.
    func wait(timeout: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        enqueue(.signal(done))
        _ = done.wait(timeout: .now() + timeout)
    }

    func takeEvents() -> [Event] {
        shared.events.withLock { events in
            defer { events = [] }
            return events
        }
    }

    // MARK: Jobs

    private static func run(_ job: Job, files: ClipboardFiles, storedPNG: (Data) -> Data?) -> [Event] {
        switch job {
        case .load:
            return [load(files)]
        case let .prepare(capture, epoch):
            guard let (entry, sizes) = entry(for: capture, files: files, storedPNG: storedPNG) else { return [] }
            return [.prepared(entry, sizes: sizes, epoch: epoch)]
        case let .store(written):
            // A copy that cannot be written is pasted as its plain text.
            let failed = written.compactMap { name, data in (try? files.write(data, name, false)) == nil ? name : nil }
            return failed.isEmpty ? [] : [.unstored(failed)]
        case let .remove(names):
            names.forEach(files.remove)
            return []
        case let .write(entries):
            guard let data = try? JSONEncoder().encode(entries) else { return [] }
            do {
                try files.write(data, ClipboardFiles.historyName, true)
            } catch {
                // The history is a cache; a failed write is picked up on the next change.
                return []
            }
            return [.saved(bytes: data.count, entries)]
        case let .signal(done):
            done.signal()
            return []
        case .save:
            // Queue.next turns a save into a write; one whose list was taken already writes nothing.
            return []
        }
    }

    /// The saved history, without the images whose file is gone, and what the folder holds.
    private static func load(_ files: ClipboardFiles) -> Event {
        let sizes = files.sizes()
        let stored = files.read(ClipboardFiles.historyName).flatMap { try? JSONDecoder().decode([ClipboardEntry].self, from: $0) } ?? []
        let entries: [ClipboardEntry] = stored.compactMap { stored in
            var entry = stored
            // A formatted copy whose file is gone leaves the text, which is in the list itself.
            entry.formats = entry.formats?.filter { sizes[$0.value] != nil }
            guard entry.kind == .image, let name = entry.imageFile else { return entry }
            return sizes[name] == nil ? nil : entry
        }
        return .loaded(entries, sizes: sizes)
    }

    /// Turns a capture into an entry and writes its files, converting its image. Nil when there is nothing to keep.
    private static func entry(for capture: ClipboardCapture, files: ClipboardFiles, storedPNG: (Data) -> Data?) -> (ClipboardEntry, sizes: [String: Int])? {
        guard case let .image(data, fallbackText) = capture.content else {
            guard var made = ClipboardEntry.made(from: capture) else { return nil }
            made.files = made.files.filter { (try? files.write($0.value, $0.key, false)) != nil }
            made.entry.formats = made.entry.formats?.filter { made.files[$0.value] != nil }
            return (made.entry, made.files.mapValues(\.count))
        }
        guard let png = storedPNG(data) else {
            return fallbackText.flatMap { ClipboardEntry.text($0, date: capture.date, sourceApp: capture.sourceApp) }.map { ($0, [:]) }
        }
        let name = "\(UUID().uuidString).png"
        do {
            try files.write(png, name, false)
        } catch {
            return nil
        }
        return (.image(named: name, png: png, date: capture.date, sourceApp: capture.sourceApp), [name: png.count])
    }
}
