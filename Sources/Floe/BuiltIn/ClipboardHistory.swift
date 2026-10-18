//
//  ClipboardHistory.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import ApplicationServices
import Combine

/// One saved clipboard item: text, a link, an image or a set of files.
nonisolated struct ClipboardEntry: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case text, link, image, file
    }

    var id: UUID
    var kind: Kind
    var text: String?
    var filePaths: [String]?
    var imageFile: String?
    var date: Date
    var pinned: Bool
    var sourceApp: String?
    /// The copy as it was formatted, when it was: a pasteboard type to the file that holds it.
    var formats: [String: String]?

    /// Every file in the clipboard folder this entry owns.
    var fileNames: [String] {
        (imageFile.map { [$0] } ?? []) + (formats.map { Array($0.values) } ?? [])
    }

    /// What identifies a duplicate for merging: same kind and same content.
    var identity: String {
        switch kind {
        case .text, .link:
            return "\(kind.rawValue):\(text ?? "")"
        case .file:
            return "file:\((filePaths ?? []).joined(separator: "\n"))"
        case .image:
            return "image:\(text ?? "")"
        }
    }

    var title: String {
        switch kind {
        case .text, .link:
            let first = (text ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return String(first.prefix(120))
        case .file:
            let paths = filePaths ?? []
            if paths.count == 1 {
                return URL(fileURLWithPath: paths[0]).lastPathComponent
            }
            return String(localized: "\(paths.count) files", bundle: .floe, comment: "How many files were copied together.")
        case .image:
            return String(localized: "Image", bundle: .floe, comment: "A copied picture.")
        }
    }
}

/// Remembers what was on the clipboard, skipping what a password manager or the system marks as private.
/// The list lives here, on the main thread; everything slow is the worker's, which answers in the order asked.
final class ClipboardHistoryStore: ObservableObject {
    /// An empty store that records nothing and writes nothing: for a model with no history to show,
    /// such as one in a test or a mode that draws the panel and exits.
    static func detached() -> ClipboardHistoryStore {
        let nowhere = ClipboardFiles(
            directory: FileManager.default.temporaryDirectory,
            sizes: { [:] },
            read: { _ in nil },
            write: { _, _, _ in
                // A detached store writes nothing.
            },
            remove: { _ in
                // Nor removes anything.
            }
        )
        return ClipboardHistoryStore(files: nowhere, monitorsPasteboard: false)
    }

    static let maxEntries = 300
    static let maxBytes: Int = 200 * 1024 * 1024
    static nonisolated let imageMaxDimension: CGFloat = 1024
    /// The original image data that may wait for the worker: five full 14-inch screenshots as TIFF, or two
    /// 5K ones, and less than the folder may hold. Past it the oldest waiting image goes, see `Queue.shed`.
    static let maxQueuedBytes: Int = 128 * 1024 * 1024

    struct Limits {
        var maxEntries = ClipboardHistoryStore.maxEntries
        var maxBytes = ClipboardHistoryStore.maxBytes
        var maxQueuedBytes = ClipboardHistoryStore.maxQueuedBytes
    }

    @Published private(set) var entries: [ClipboardEntry] = []
    /// Called in the resident once the history on disk changed, with what changed since the last call.
    var onSaved: ((ClipboardChange) -> Void)?

    /// What the folder holds once the worker has caught up: counted from disk at load, then kept.
    var storedBytes: Int {
        ledger.total
    }

    /// The original image data held by copies still waiting for the worker.
    var queuedBytes: Int {
        worker.queuedBytes
    }

    let files: ClipboardFiles
    private let remote: ((PanelPacket) -> Void)?
    private let limits: Limits
    private let worker: ClipboardHistoryWorker
    private var ledger = ClipboardByteLedger()
    /// The list as last written, which the next change is counted from.
    private var written: [ClipboardEntry] = []
    /// Files the list no longer uses, removed by the worker with the next save.
    private var unusedFiles: [String] = []
    /// Goes up with every Clear, so a copy still being processed when it happened is not kept.
    private var epoch = 0
    private(set) var isLoaded = false
    private var clearsWhenLoaded = false
    private var watcher: ClipboardWatcher?
    private var recordingObserver: AnyCancellable?

    static var directory: URL {
        Paths.support.appendingPathComponent("Clipboard", isDirectory: true)
    }

    init(
        files: ClipboardFiles = .onDisk(ClipboardHistoryStore.directory),
        limits: Limits = Limits(),
        monitorsPasteboard: Bool = true,
        remote: ((PanelPacket) -> Void)? = nil,
        storedPNG: @escaping @Sendable (Data) -> Data? = ClipboardHistoryStore.storedPNG
    ) {
        self.files = files
        self.remote = remote
        self.limits = limits
        worker = ClipboardHistoryWorker(files: files, maxQueuedBytes: limits.maxQueuedBytes, storedPNG: storedPNG)
        Task { @MainActor [weak self, wakes = worker.wakes] in
            for await _ in wakes {
                self?.applyEvents()
            }
        }
        if remote == nil {
            worker.load()
        }
        if monitorsPasteboard, !ClipboardApps.ownHistoryIsParked {
            startMonitoring()
        }
    }

    // MARK: Monitoring

    private func startMonitoring() {
        let board = NSPasteboard.general
        let watcher = ClipboardWatcher(
            changeCount: { board.changeCount },
            read: { ClipboardCapture.reading(board) },
            isRecording: { AppSettings.shared.recordsClipboardHistory },
            deliver: { [weak self] in self?.take($0) }
        )
        watcher.start()
        self.watcher = watcher
        // Copies still waiting when recording stops, or when another app takes the clipboard, are not kept.
        let settings = AppSettings.shared
        recordingObserver = settings.$clipboardHandler.combineLatest(settings.$clipboardHistoryEnabled)
            .map { ClipboardApps.records(handler: $0, historyEnabled: $1) }
            .removeDuplicates()
            .sink { [weak self] records in
                if !records {
                    self?.dropPendingCopies()
                }
            }
    }

    /// What the watcher read: a copy to keep, or an entry Floe put back itself, which only moves to the top.
    func take(_ reading: ClipboardCapture.Reading) {
        switch reading {
        case let .copy(capture): record(capture)
        case let .own(id): touch(id)
        case .skipped, .empty: break
        }
    }

    /// Text and files join the list at once, and the worker only writes their formatted copies. An image is
    /// the worker's to convert, and so is anything copied before the saved list is read: it joins after that.
    func record(_ capture: ClipboardCapture) {
        guard isLoaded, capture.imageBytes == 0 else {
            worker.prepare(capture, epoch: epoch)
            return
        }
        guard let made = ClipboardEntry.made(from: capture) else { return }
        worker.store(made.files)
        insert(made.entry, sizes: made.files.mapValues(\.count))
    }

    /// Forgets the copies not in the list yet: the waiting ones now, the one being converted when it returns.
    func dropPendingCopies() {
        epoch += 1
        worker.discardQueuedCopies()
    }

    /// Takes what the worker has finished, in the order it finished it.
    private func applyEvents() {
        for event in worker.takeEvents() {
            switch event {
            case let .loaded(stored, sizes):
                ledger = ClipboardByteLedger(sizes: sizes)
                entries = stored
                written = stored
                isLoaded = true
                if clearsWhenLoaded {
                    clearsWhenLoaded = false
                    removeUnpinned()
                }
                onSaved?(.reload)
            case let .prepared(entry, sizes, epoch):
                if epoch == self.epoch {
                    insert(entry, sizes: sizes)
                } else {
                    worker.remove(entry.fileNames)
                }
            case let .saved(bytes, list):
                ledger.set(ClipboardFiles.historyName, bytes: bytes)
                if let change = ClipboardChange.between(written, list) {
                    written = list
                    onSaved?(change)
                }
            case let .unstored(names):
                forget(names)
            }
        }
    }

    /// Stops naming formatted copies whose file was never written: the entry keeps its text.
    private func forget(_ names: [String]) {
        for index in entries.indices {
            entries[index].formats = entries[index].formats?.filter { !names.contains($0.value) }
        }
        names.forEach { ledger.remove($0) }
        save()
    }

    /// Waits for the worker to finish what it was asked, so the disk matches the list. For quitting.
    func flush(timeout: TimeInterval = 5) {
        // Twice: finished copies join the list in the first round and are written in the second.
        for _ in 0 ..< 2 {
            worker.wait(timeout: timeout)
            applyEvents()
        }
    }

    // MARK: Mutations

    /// Adds an entry, merging a duplicate into it and keeping its pin.
    private func insert(_ entry: ClipboardEntry, sizes: [String: Int]) {
        var next = entry
        for (name, bytes) in sizes {
            ledger.set(name, bytes: bytes)
        }
        if let existing = entries.first(where: { $0.identity == next.identity }) {
            next.pinned = existing.pinned
            next.id = existing.id
            existing.fileNames.filter { !next.fileNames.contains($0) }.forEach(removeFile)
            entries.removeAll { $0.id == existing.id }
        }
        place(next)
        enforceEntryCap()
        enforceByteCap()
        save()
    }

    /// Newest first by the time of the copy, so an image that took a while lands under what was copied after it.
    private func place(_ entry: ClipboardEntry) {
        entries.insert(entry, at: entries.partitioningIndex { $0.date <= entry.date })
    }

    /// Moves an entry to the top as copied now: Floe put it back on the clipboard itself.
    func touch(_ id: UUID, date: Date = Date()) {
        guard remote == nil, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.date = date
        place(entry)
        save()
    }

    /// Toggles a pin in the resident, or forwards its ID without mutating a foreground snapshot.
    func togglePin(_ entry: ClipboardEntry) {
        if let remote {
            remote(.pinClipboard(entry.id)); return
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned.toggle()
        save()
    }

    /// Removes an entry and its image through the resident; stale entry IDs are harmless.
    func delete(_ entry: ClipboardEntry) {
        if let remote {
            remote(.deleteClipboard(entry.id)); return
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].fileNames.forEach(removeFile)
        entries.remove(at: index)
        save()
    }

    /// Removes everything not pinned; pins survive Clear. Copies still being processed are dropped too.
    func clear() {
        if let remote {
            remote(.clearClipboard); return
        }
        dropPendingCopies()
        // Nothing is written before the load, or an empty list would replace the saved one.
        clearsWhenLoaded = !isLoaded
        if isLoaded {
            removeUnpinned()
        }
    }

    private func removeUnpinned() {
        for entry in entries where !entry.pinned {
            entry.fileNames.forEach(removeFile)
        }
        entries = entries.filter(\.pinned)
        save()
    }

    private func enforceEntryCap() {
        guard entries.count > limits.maxEntries else { return }
        var (unpinned, pinned) = entries.partitioned(by: \.pinned)
        unpinned = Array(unpinned.prefix(max(0, limits.maxEntries - pinned.count)))
        let removed = Set(entries.map(\.id)).subtracting(pinned.map(\.id) + unpinned.map(\.id))
        for entry in entries where removed.contains(entry.id) {
            entry.fileNames.forEach(removeFile)
        }
        entries = pinned + unpinned
        entries.sort { $0.date > $1.date }
    }

    /// Drops the oldest unpinned entries (and their files) until the folder fits the byte cap.
    private func enforceByteCap() {
        guard ledger.total > limits.maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) where !entry.pinned {
            entry.fileNames.forEach(removeFile)
            entries.removeAll { $0.id == entry.id }
            if ledger.total <= limits.maxBytes {
                break
            }
        }
    }

    // MARK: Storage

    /// Has the worker remove the files the list dropped, then write the list as it is now.
    private func save() {
        if !unusedFiles.isEmpty {
            worker.remove(unusedFiles)
            unusedFiles = []
        }
        worker.save(entries)
    }

    private func removeFile(_ name: String) {
        guard !name.isEmpty else { return }
        ledger.remove(name)
        unusedFiles.append(name)
    }
}

extension ClipboardHistoryStore {
    /// Only the resident writes history; the panel's copy takes what the resident says changed.
    /// Before its first read of the file has finished, a change could be older than what that read finds, so it reads again.
    func apply(_ change: ClipboardChange) {
        guard remote != nil else { return }
        switch change {
        case .reload:
            worker.load()
        case let .entries(changed, removed):
            guard isLoaded else {
                worker.load()
                return
            }
            let replaced = Set(removed + changed.map(\.id))
            entries = (entries.filter { !replaced.contains($0.id) } + changed).sorted { $0.date > $1.date }
        }
    }
}
