//
//  FileSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import AsyncAlgorithms
import Combine

nonisolated struct FileResult: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let displayPath: String
    let contentType: String?
    let lastUsed: Date?
    /// The offsets of the letters of the name that the query matched, when the index found the file.
    var matched: [Int] = []
    var id: String {
        url.path
    }
}

final class FileSearch: ObservableObject {
    @Published private(set) var results: [FileResult] = []
    @Published private(set) var isSearching = false

    private var metadataQuery: NSMetadataQuery?
    /// Queries wait here until typing pauses. Each carries the round it was typed in, so one that
    /// settles after `cancel()` is dropped.
    private let queries = AsyncStream.makeStream(of: (round: Int, text: String).self, bufferingPolicy: .bufferingNewest(1))
    private var round = 0
    private var settling: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// Whether what Spotlight has found so far is published while it is still gathering.
    private let publishesProgress: Bool
    /// Floe's own index of file names, which answers in place of Spotlight once it is switched on and built.
    private let index: FileIndexService
    private var answering: Task<Void, Never>?

    init(publishesProgress: Bool = false, index: FileIndexService = .shared) {
        self.publishesProgress = publishesProgress
        self.index = index
        let stream = queries.stream
        settling = Task { @MainActor [weak self] in
            for await query in stream.debounce(for: .milliseconds(150)) {
                guard let self, query.round == round else { continue }
                start(query.text)
            }
        }
    }

    func search(_ query: String) {
        guard Self.asksIndex(query, state: index.state) else {
            queries.continuation.yield((round, query))
            return
        }
        // The round moves on, so a query still waiting for its pause is dropped and an older answer does not land late.
        round += 1
        let asked = round
        answering?.cancel()
        answering = Task { [weak self, index] in
            let files = await Self.files(matching: query, in: index)
            guard let self, asked == round else { return }
            guard let files else {
                // Not built yet, or switched off since: Spotlight answers as before.
                queries.continuation.yield((round, query))
                return
            }
            stopQuery()
            results = files
            isSearching = false
        }
    }

    /// Whether a query goes to Floe's index first. The recent files of an empty query are Spotlight's to know:
    /// the index holds names and no dates.
    static nonisolated func asksIndex(_ query: String, state: FileIndexService.State) -> Bool {
        state != .off && !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @concurrent
    private static nonisolated func files(matching query: String, in index: FileIndexService) async -> [FileResult]? {
        index.files(matching: query)
    }

    func cancel() {
        round += 1
        answering?.cancel()
        stopQuery()
        results = []
        isSearching = false
    }

    func open(_ file: FileResult) {
        NSWorkspace.shared.openWithoutWaiting(file.url)
    }

    func reveal(_ file: FileResult) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    private func start(_ query: String) {
        stopQuery()
        isSearching = true
        let metadata = NSMetadataQuery()
        metadata.searchScopes = [NSMetadataQueryUserHomeScope]
        if query.isEmpty {
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            metadata.predicate = NSPredicate(format: "%K >= %@", "kMDItemLastUsedDate", weekAgo as NSDate)
        } else {
            metadata.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(query)*")
        }
        metadata.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        let center = NotificationCenter.default
        observers = [
            center.addMainObserver(forName: .NSMetadataQueryDidFinishGathering, object: metadata) { [weak self] in self?.finish() },
            center.addMainObserver(forName: .NSMetadataQueryDidUpdate, object: metadata) { [weak self] in self?.finish() },
        ]
        if publishesProgress {
            observers.append(center.addMainObserver(forName: .NSMetadataQueryGatheringProgress, object: metadata) { [weak self] in
                self?.publishProgress()
            })
        }
        metadataQuery = metadata
        metadata.start()
    }

    private func finish() {
        guard let metadata = metadataQuery else { return }
        metadata.disableUpdates()
        results = Self.files(in: metadata)
        isSearching = false
        stopQuery()
    }

    private func publishProgress() {
        guard let metadata = metadataQuery else { return }
        metadata.disableUpdates()
        results = Self.files(in: metadata)
        metadata.enableUpdates()
    }

    /// The first files of a query that are worth showing. The query's updates must be off while this reads it.
    private static func files(in metadata: NSMetadataQuery) -> [FileResult] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var files: [FileResult] = []
        for item in metadata.results.prefix(50) {
            guard let metadataItem = item as? NSMetadataItem else { continue }
            let url: URL?
            if let direct = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL {
                url = direct
            } else if let path = metadataItem.value(forAttribute: NSMetadataItemPathKey) as? String {
                url = URL(fileURLWithPath: path)
            } else {
                continue
            }
            guard let fileURL = url else { continue }
            let path = fileURL.path
            if path.contains("/Library/") {
                continue
            }
            if fileURL.pathComponents.contains(where: { $0.hasPrefix(".") }) {
                continue
            }
            // Apps already have their own scope.
            if fileURL.lastPathComponent.hasSuffix(".app") {
                continue
            }
            let folder = fileURL.deletingLastPathComponent().path
            let displayPath = folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
            files.append(FileResult(
                url: fileURL,
                name: (metadataItem.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? fileURL.lastPathComponent,
                displayPath: displayPath,
                contentType: metadataItem.value(forAttribute: "kMDItemContentType") as? String,
                lastUsed: metadataItem.value(forAttribute: "kMDItemLastUsedDate") as? Date
            ))
        }
        return files
    }

    private func stopQuery() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        metadataQuery?.stop()
        metadataQuery = nil
    }

    isolated deinit {
        answering?.cancel()
        settling?.cancel()
        queries.continuation.finish()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        metadataQuery?.stop()
    }
}
