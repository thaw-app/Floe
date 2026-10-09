//
//  FileSearchScope.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import Foundation

/// `files invoice`: the files Spotlight or Floe's own index finds, listed as they come in.
/// Only the main thread touches it; the end of a stream hops back there before it does.
final class FileSearchScope: SearchScope {
    let keyword = "files"
    let title = String(localized: "Files", bundle: .floe)
    let emptyTitle = String(localized: "No files match", bundle: .floe)

    /// Its own search, so the file search view's results are left alone.
    private lazy var search = FileSearch(publishesProgress: true, index: index)
    private let index: FileIndexService
    /// Bumped per query, so a stream that ends late does not stop the search that replaced it.
    private var round = 0
    private var subscriptions: Set<AnyCancellable> = []

    init(index: FileIndexService = .shared) {
        self.index = index
    }

    func results(for _: String, context _: SearchContext) -> [RootItem] {
        []
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        round += 1
        let started = round
        let search = search
        subscriptions = []
        search.cancel()
        let (stream, continuation) = AsyncStream.makeStream(of: [RootItem].self, bufferingPolicy: .bufferingNewest(1))
        search.$results.dropFirst()
            .sink { continuation.yield($0.map(RootItem.file)) }
            .store(in: &subscriptions)
        // Searching stops once per query, when Spotlight has gathered everything.
        search.$isSearching.dropFirst().filter { !$0 }
            .sink { _ in continuation.finish() }
            .store(in: &subscriptions)
        continuation.onTermination = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.stop(round: started) }
        }
        search.search(text)
        return stream
    }

    /// Stops the search a stream was following, unless a newer query has taken it over.
    private func stop(round started: Int) {
        guard started == round else { return }
        subscriptions = []
        search.cancel()
    }
}
