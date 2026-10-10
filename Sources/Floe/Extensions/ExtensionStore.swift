//
//  ExtensionStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

nonisolated struct StoreListing: Identifiable, Hashable {
    let name: String
    var id: String {
        name
    }
}

/// Finds extensions by name with the launcher's matcher, best match first. The name is the folder's, the one
/// thing known of every extension before any of them is asked for.
nonisolated enum StoreSearch {
    /// A name's words apart and run together, so "proton pass" and "protonpass" both find proton-pass.
    static func forms(_ text: String) -> (spaced: String, joined: String) {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        return (words.joined(separator: " "), words.joined())
    }

    static func score(_ query: String, name: String) -> Int? {
        let wanted = forms(query)
        let candidate = forms(name)
        return [Fuzzy.score(wanted.spaced, candidate.spaced), Fuzzy.score(wanted.joined, candidate.joined)].compactMap(\.self).max()
    }

    /// Everything, in the catalog's order, for a query with nothing to match on.
    static func results(_ catalog: [StoreListing], query: String) -> [StoreListing] {
        guard !forms(query).joined.isEmpty else { return catalog }
        return catalog.enumerated()
            .compactMap { index, listing in score(query, name: listing.name).map { (listing, $0, index) } }
            // Equal scores keep the catalog's order, which a plain sort does not promise.
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}

struct StoreCommand: Identifiable, Hashable {
    let name: String
    let title: String
    let description: String?
    let mode: String
    var id: String {
        name
    }
}

struct StoreDetails: Hashable {
    let name: String
    let title: String
    let description: String?
    let author: String?
    let iconURL: URL?
    let commands: [StoreCommand]
}

@MainActor
final class ExtensionStore: ObservableObject {
    static let shared = ExtensionStore()

    @Published private(set) var catalog: [StoreListing] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var busy: Set<String> = []
    var onInstalled: () -> Void = { /* set by the settings process */ }

    var detailsCache: [String: StoreDetails] = [:]
    var detailsTasks: [String: Task<StoreDetails?, Never>] = [:]
    var iconTasks: [URL: Task<String?, Never>] = [:]
    var iconFiles: [URL: String] = [:]
    private var latestShaCache: [String: String] = [:]
    /// Reads one file of the repository. Tests answer for themselves.
    let fetch: @Sendable (URL) async throws -> Data
    let iconFolder: URL

    /// How long a row stays on screen before its details are asked for: rows that typing or scrolling passes over ask for nothing.
    static let settleDelay: Duration = .milliseconds(350)

    init(
        catalog: [String] = [],
        iconFolder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("floe-store-icons", isDirectory: true),
        fetch: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }
    ) {
        self.catalog = catalog.map(StoreListing.init(name:))
        self.iconFolder = iconFolder
        self.fetch = fetch
    }

    private var catalogTask: Task<Void, Never>?

    private static let catalogFileName = "store-catalog.json"
    static let recordFileName = ".floe-store.json"
    private static let cacheLifetime: TimeInterval = 24 * 3600
    private static let repoAPI = "https://api.github.com/repos/raycast/extensions"
    static nonisolated let rawBase = "https://raw.githubusercontent.com/raycast/extensions/main/extensions"

    private var catalogURL: URL {
        Paths.support.appendingPathComponent(Self.catalogFileName)
    }

    func cachedDetails(for name: String) -> StoreDetails? {
        detailsCache[name]
    }

    func loadCatalog(force: Bool = false) async {
        if isLoading {
            await catalogTask?.value
            return
        }
        if !force, let cached = readCatalogCache(), !cached.isEmpty {
            catalog = cached.map(StoreListing.init(name:))
            return
        }
        isLoading = true
        error = nil
        let task = Task {
            do {
                let names = try await Self.fetchExtensionNames()
                try? Self.writeCatalogCache(names: names)
                self.catalog = names.map(StoreListing.init(name:))
            } catch {
                self.error = String(localized: "Couldn't load the store: \(error.localizedDescription)", bundle: .floe, comment: "The placeholder is the reason.")
            }
        }
        catalogTask = task
        await task.value
        isLoading = false
        catalogTask = nil
    }

    func install(_ name: String) async {
        guard !busy.contains(name) else { return }
        busy.insert(name)
        error = nil
        defer { busy.remove(name) }
        do {
            let fetched = try await Self.fetchExtensionCopy(name: name)
            defer { try? FileManager.default.removeItem(at: fetched.workDir) }
            try await Self.runBunInstall(in: fetched.extensionDir)
            let folderCommit = await latestCommit(touching: name, askingAgain: true)
            try Self.swapIn(name: name, staged: fetched.extensionDir, commit: Self.revisionToRecord(folderCommit: folderCommit, repositoryCommit: fetched.commit))
            onInstalled()
        } catch let failure as StoreFailure {
            self.error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func update(_ name: String) async {
        guard !busy.contains(name) else { return }
        busy.insert(name)
        error = nil
        defer { busy.remove(name) }
        do {
            let fetched = try await Self.fetchExtensionCopy(name: name)
            defer { try? FileManager.default.removeItem(at: fetched.workDir) }
            try await Self.runBunInstall(in: fetched.extensionDir)
            let folderCommit = await latestCommit(touching: name, askingAgain: true)
            try Self.swapIn(name: name, staged: fetched.extensionDir, commit: Self.revisionToRecord(folderCommit: folderCommit, repositoryCommit: fetched.commit))
            try? FileManager.default.removeItem(at: fetched.workDir)
            onInstalled()
        } catch let failure as StoreFailure {
            self.error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func remove(_ name: String) {
        let folder = Paths.extensions.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            let receipt = try ReceiptStore.trash(folder, as: .extensionRemoved, subject: name)
            if AppSettings.shared.keepsReceipts {
                ReceiptStore.shared.add(receipt)
            }
            onInstalled()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    func isInstalled(_ name: String) -> Bool {
        let folder = Paths.extensions.appendingPathComponent(name, isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("package.json").path)
    }

    func hasUpdate(_ name: String) async -> Bool {
        guard isInstalled(name), let recorded = Self.recordedCommit(for: name) else { return false }
        guard let latest = await latestCommit(touching: name) else { return false }
        guard latest != recorded else { return false }
        // An install from before the folder's commit was what is recorded holds the repository's commit of that
        // day. When that one already has the folder's newest change in it, nothing is new: the record is put right.
        if await holds(recorded, the: latest) {
            Self.record(commit: latest, for: name)
            return false
        }
        return true
    }

    /// Whether the history of `commit` has `change` in it, asked of GitHub. False when it cannot be asked.
    private func holds(_ commit: String, the change: String) async -> Bool {
        guard let url = URL(string: "\(Self.repoAPI)/compare/\(change)...\(commit)?per_page=1"),
              let (data, _) = try? await URLSession.shared.data(for: Self.apiRequest(url: url)) else { return false }
        return Self.isAtOrPast(in: data)
    }

    /// GitHub's answer to "compare base to head": whether head is the base or comes after it.
    static nonisolated func isAtOrPast(in data: Data) -> Bool {
        let status = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["status"] as? String
        return status == "ahead" || status == "identical"
    }

    /// Writes the commit an installed extension is at into its record, keeping the day it was installed.
    static func record(commit: String, for name: String, in extensions: URL = Paths.extensions) {
        let file = extensions.appendingPathComponent(name, isDirectory: true).appendingPathComponent(recordFileName)
        guard let data = try? Data(contentsOf: file), let old = try? JSONDecoder().decode(Record.self, from: data),
              let updated = try? JSONEncoder().encode(Record(name: old.name, commit: commit, installedAt: old.installedAt)) else { return }
        try? updated.write(to: file, options: .atomic)
    }

    /// The newest commit that changed the extension's folder: what an install records and what an update check
    /// compares, so the two are the same kind of thing. The repository's own newest commit is neither: it moves
    /// with every change to any extension. Nil when GitHub cannot be asked.
    private func latestCommit(touching name: String, askingAgain: Bool = false) async -> String? {
        if !askingAgain, let cached = latestShaCache[name] {
            return cached
        }
        guard let url = URL(string: "\(Self.repoAPI)/commits?path=extensions/\(name)&per_page=1"),
              let (data, _) = try? await URLSession.shared.data(for: Self.apiRequest(url: url)),
              let sha = Self.newestCommit(in: data) else { return nil }
        latestShaCache[name] = sha
        return sha
    }

    /// The first commit in GitHub's answer to "the commits of this path", which lists the newest first.
    static nonisolated func newestCommit(in data: Data) -> String? {
        let commits = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        return commits?.first?["sha"] as? String
    }

    /// What to record for an installed copy: the newest commit of its folder, or the repository's when GitHub
    /// could not say. With the second an update is offered once more than it should be, and never missed.
    static nonisolated func revisionToRecord(folderCommit: String?, repositoryCommit: String) -> String {
        folderCommit ?? repositoryCommit
    }

    // MARK: - Catalog fetching

    private static func apiRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Floe", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func fetchExtensionNames() async throws -> [String] {
        guard let rootURL = URL(string: "\(repoAPI)/git/trees/main") else {
            throw StoreFailure(message: String(localized: "Could not find the extensions folder in the Raycast repository.", bundle: .floe))
        }
        let (rootData, _) = try await URLSession.shared.data(for: apiRequest(url: rootURL))
        guard let root = try JSONSerialization.jsonObject(with: rootData) as? [String: Any],
              let entries = root["tree"] as? [[String: Any]],
              let sha = entries.first(where: { ($0["path"] as? String) == "extensions" && ($0["type"] as? String) == "tree" })?["sha"] as? String
        else { throw StoreFailure(message: String(localized: "Could not find the extensions folder in the Raycast repository.", bundle: .floe)) }
        guard let listURL = URL(string: "\(repoAPI)/git/trees/\(sha)") else {
            throw StoreFailure(message: String(localized: "Could not find the extensions folder in the Raycast repository.", bundle: .floe))
        }
        let (listData, _) = try await URLSession.shared.data(for: apiRequest(url: listURL))
        guard let list = try JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let folders = list["tree"] as? [[String: Any]]
        else {
            throw StoreFailure(message: String(localized: "Could not list the extensions in the Raycast repository.", bundle: .floe))
        }
        return folders
            .filter { ($0["type"] as? String) == "tree" }
            .compactMap { $0["path"] as? String }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func readCatalogCache() -> [String]? {
        guard let data = try? Data(contentsOf: catalogURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fetchedAt = json["fetchedAt"] as? Double,
              Date().timeIntervalSince1970 - fetchedAt < Self.cacheLifetime,
              let names = json["names"] as? [String] else { return nil }
        return names
    }

    private static func writeCatalogCache(names: [String]) throws {
        Paths.prepareSupportFolders()
        let json: [String: Any] = ["fetchedAt": Date().timeIntervalSince1970, "names": names]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: ExtensionStore.shared.catalogURL, options: .atomic)
    }
}
