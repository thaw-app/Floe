//
//  ExtensionAccess.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What an extension has been seen to reach, as its process reported it: a record, not a limit.
nonisolated struct ExtensionAccess: Codable, Equatable, Sendable {
    /// Hosts it contacted.
    var hosts: [String] = []
    /// Places it read from and places it changed, by folder.
    var reads: [String] = []
    var writes: [String] = []
    /// Programs it started.
    var programs: [String] = []
    /// When the first and the latest of these were seen.
    var since: Date?
    var latest: Date?

    var isEmpty: Bool {
        hosts.isEmpty && reads.isEmpty && writes.isEmpty && programs.isEmpty
    }

    /// Adds what a report holds that is not here yet. Answers whether anything was new.
    mutating func add(_ report: [String: Any], at date: Date) -> Bool {
        var changed = false
        func merge(_ list: inout [String], _ key: String) {
            let fresh = (report[key] as? [String] ?? []).filter { !$0.isEmpty && !list.contains($0) }
            guard !fresh.isEmpty else { return }
            // An extension gone wrong must not fill the disk: the first of each kind are kept.
            list = Array((list + fresh).sorted().prefix(Self.limit))
            changed = true
        }
        merge(&hosts, "hosts")
        merge(&reads, "reads")
        merge(&writes, "writes")
        merge(&programs, "programs")
        if changed {
            since = since ?? date
            latest = date
        }
        return changed
    }

    static let limit = 200
}

/// The record of every extension, in a file. Read from the file each time: the launcher writes it and the
/// settings window, another process, shows it.
final nonisolated class ExtensionAccessStore: Sendable {
    static let shared = ExtensionAccessStore()

    private let file: URL

    init(file: URL = Paths.support.appendingPathComponent("ExtensionAccess.json")) {
        self.file = file
    }

    private var all: [String: ExtensionAccess] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: ExtensionAccess].self, from: $0) } ?? [:]
    }

    func access(of extensionName: String) -> ExtensionAccess {
        all[extensionName] ?? ExtensionAccess()
    }

    /// Takes in one report from an extension's process. Nothing is written when it holds nothing new.
    func record(_ report: [String: Any], for extensionName: String, at date: Date = Date()) {
        var everything = all
        var access = everything[extensionName] ?? ExtensionAccess()
        guard access.add(report, at: date) else { return }
        everything[extensionName] = access
        write(everything)
    }

    func forget(_ extensionName: String) {
        var everything = all
        guard everything.removeValue(forKey: extensionName) != nil else { return }
        write(everything)
    }

    private func write(_ everything: [String: ExtensionAccess]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(everything).write(to: file, options: .atomic)
    }
}
