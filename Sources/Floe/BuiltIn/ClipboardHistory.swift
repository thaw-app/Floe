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
nonisolated struct ClipboardEntry: Identifiable, Codable, Sendable {
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
    /// Whether the user's own store exists yet: it starts with the first thing that reads it.
    private static var hasShared = false
    static var remoteMutation: ((PanelPacket) -> Void)?
    static let shared: ClipboardHistoryStore = {
        hasShared = true
        return ClipboardHistoryStore(monitorsPasteboard: remoteMutation == nil, remote: remoteMutation)
    }()

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
    var onSnapshotSaved: () -> Void = {}

    /// What the folder holds once the worker has caught up: counted from disk at load, then kept.
    var storedBytes: Int {
        ledger.total
    }

    /// The original image data held by copies still waiting for the worker.
    var queuedBytes: Int {
        worker.queuedBytes
    }

    private let files: ClipboardFiles
    private let remote: ((PanelPacket) -> Void)?
    private let limits: Limits
    private let worker: ClipboardHistoryWorker
    private var ledger = ClipboardByteLedger()
    /// Image files the list no longer uses, removed by the worker with the next save.
    private var unusedFiles: [String] = []
    /// Goes up with every Clear, so a copy still being processed when it happened is not kept.
    private var epoch = 0
    private var isLoaded = false
    private var clearsWhenLoaded = false
    private var lastChangeCount = 0
    private var timer: Timer?
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
        worker.start()
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
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        timer = Timer.scheduledOnMain(withTimeInterval: 0.5, repeats: true) { [weak self] in
            self?.poll()
        }
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

    private func poll() {
        guard AppSettings.shared.recordsClipboardHistory else { return }
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        guard let capture = ClipboardCapture.read(board) else { return }
        record(capture)
    }

    /// Hands a copy to the worker; it joins the list once it is ready, after the copies before it.
    func record(_ capture: ClipboardCapture) {
        worker.prepare(capture, epoch: epoch)
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
                isLoaded = true
                if clearsWhenLoaded {
                    clearsWhenLoaded = false
                    removeUnpinned()
                }
                onSnapshotSaved()
            case let .prepared(entry, bytes, epoch):
                if epoch == self.epoch {
                    insert(entry, bytes: bytes)
                } else if let name = entry.imageFile {
                    worker.remove([name])
                }
            case let .saved(bytes):
                ledger.set(ClipboardFiles.historyName, bytes: bytes)
                onSnapshotSaved()
            }
        }
    }

    /// Waits for the worker to finish what it was asked, so the disk matches the list. For quitting.
    func flush(timeout: TimeInterval = 5) {
        // Twice: finished copies join the list in the first round and are written in the second.
        for _ in 0 ..< 2 {
            worker.wait(timeout: timeout)
            applyEvents()
        }
    }

    /// Flushes the user's store, if this run ever started it.
    static func flushShared() {
        if hasShared {
            shared.flush()
        }
    }

    // MARK: Mutations

    /// Adds an entry, merging a duplicate to the top and keeping its pin.
    private func insert(_ entry: ClipboardEntry, bytes: Int) {
        var next = entry
        if let name = next.imageFile {
            ledger.set(name, bytes: bytes)
        }
        if let existing = entries.first(where: { $0.identity == next.identity }) {
            next.pinned = existing.pinned
            next.id = existing.id
            if existing.kind == .image, existing.imageFile != next.imageFile {
                removeImageFile(existing.imageFile)
            }
            entries.removeAll { $0.id == existing.id }
        }
        entries.insert(next, at: 0)
        enforceEntryCap()
        enforceByteCap()
        save()
    }

    /// Only the resident writes history. The mirror reloads after its atomic save, without
    /// asking the resident to encode a second, potentially large clipboard snapshot.
    func reloadMirror() {
        guard remote != nil else { return }
        worker.load()
    }

    func togglePin(_ entry: ClipboardEntry) {
        if let remote {
            remote(.pinClipboard(entry.id)); return
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned.toggle()
        save()
    }

    func delete(_ entry: ClipboardEntry) {
        if let remote {
            remote(.deleteClipboard(entry.id)); return
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        removeImageFile(entries[index].imageFile)
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
            removeImageFile(entry.imageFile)
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
            removeImageFile(entry.imageFile)
        }
        entries = pinned + unpinned
        entries.sort { $0.date > $1.date }
    }

    /// Drops the oldest unpinned entries (and their images) until the folder fits the byte cap.
    private func enforceByteCap() {
        guard ledger.total > limits.maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) where !entry.pinned {
            removeImageFile(entry.imageFile)
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

    private func removeImageFile(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        ledger.remove(name)
        unusedFiles.append(name)
    }
}

extension ClipboardHistoryStore {
    /// The PNG stored for a copied image, or nil when the data is not an image.
    @Sendable static nonisolated func storedPNG(_ data: Data) -> Data? {
        downsampledPNG(data) ?? NSImage(data: data).flatMap(downscaledPNG)
    }

    /// ImageIO scales while it decodes, so the copied image never exists at full size. Drawn through
    /// AppKit, each one left a full-size bitmap in the system's caches. Nil for what ImageIO cannot read.
    static nonisolated func downsampledPNG(_ data: Data) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(imageMaxDimension),
        ]
        let png = NSMutableData()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : nil
    }

    /// For what only AppKit reads, a PDF above all: scales an image to at most `imageMaxDimension` on its longer side.
    static nonisolated func downscaledPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let longest = max(width, height)
        if longest <= Int(imageMaxDimension), let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        let scale = imageMaxDimension / CGFloat(longest)
        let size = NSSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        scaled.unlockFocus()
        guard let scaledTIFF = scaled.tiffRepresentation,
              let scaledRep = NSBitmapImageRep(data: scaledTIFF)
        else { return nil }
        return scaledRep.representation(using: .png, properties: [:])
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let name = entry.imageFile else { return nil }
        return NSImage(contentsOf: files.directory.appendingPathComponent(name))
    }
}
