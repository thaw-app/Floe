//
//  ProcessSearchScopes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `kill thaw`: the running processes that match, to quit one by looking at it.
struct ProcessSearchScope: SearchScope {
    let keyword = Processes.keyword
    let title = String(localized: "Running Processes", bundle: .floe)
    let emptyTitle = String(localized: "No running process matches", bundle: .floe)
    var running: @Sendable () -> [RunningProcess] = { Processes.running() }

    func results(for text: String, context _: SearchContext) -> [RootItem] {
        Processes.matching(text, in: running()).map(RootItem.process)
    }
}

/// `port 3000`: the processes listening there. The answer comes from a program, so it is asked for off the main thread.
struct PortSearchScope: SearchScope {
    let keyword = Processes.portKeyword
    let title = String(localized: "Listening on the Port", bundle: .floe)
    let emptyTitle = String(localized: "Nothing is listening on that port", bundle: .floe)
    var running: @Sendable () -> [RunningProcess] = { Processes.running() }
    var listening: @Sendable (Int) -> [Int32] = { Processes.listening(on: $0) }

    /// Without a port after it the word is not a scope, so "port authority" stays an ordinary search.
    func text(in context: SearchContext) -> String? {
        Processes.port(in: context.trimmed).map(String.init)
    }

    func results(for _: String, context _: SearchContext) -> [RootItem] {
        []
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        guard let port = Int(text) else { return nil }
        let (stream, continuation) = AsyncStream.makeStream(of: [RootItem].self)
        Task { @concurrent [running, listening] in
            let pids = Set(listening(port))
            continuation.yield(running().filter { pids.contains($0.pid) }.map(RootItem.process))
            continuation.finish()
        }
        return stream
    }
}
