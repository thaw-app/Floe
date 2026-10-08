//
//  ExtensionStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Subprocess
import System

struct StoreListing: Identifiable, Hashable {
    let name: String
    var id: String {
        name
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

    private var detailsCache: [String: StoreDetails] = [:]
    private var latestShaCache: [String: String] = [:]
    private var catalogTask: Task<Void, Never>?

    private static let catalogFileName = "store-catalog.json"
    private static let recordFileName = ".floe-store.json"
    private static let cacheLifetime: TimeInterval = 24 * 3600
    private static let repoAPI = "https://api.github.com/repos/raycast/extensions"
    private static nonisolated let rawBase = "https://raw.githubusercontent.com/raycast/extensions/main/extensions"

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

    func details(for name: String) async -> StoreDetails? {
        if let cached = detailsCache[name] {
            return cached
        }
        guard let url = URL(string: "\(Self.rawBase)/\(name)/package.json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let parsed = Self.parseDetails(name: name, manifest: manifest)
            detailsCache[name] = parsed
            return parsed
        } catch {
            return nil
        }
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
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
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
        return latest != recorded
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

    // MARK: - Details parsing

    static nonisolated func parseDetails(name: String, manifest: [String: Any]) -> StoreDetails {
        let title = manifest["title"] as? String ?? name
        let description = manifest["description"] as? String
        let author: String? = {
            if let value = manifest["author"] as? String {
                return value
            }
            if let dict = manifest["author"] as? [String: Any] {
                return dict["name"] as? String
            }
            if let owner = manifest["owner"] as? String {
                return owner
            }
            return nil
        }()
        let iconURL = iconURL(for: name, icon: manifest["icon"])
        let commands = (manifest["commands"] as? [[String: Any]] ?? []).compactMap { command -> StoreCommand? in
            guard let commandName = command["name"] as? String else { return nil }
            return StoreCommand(
                name: commandName,
                title: command["title"] as? String ?? commandName,
                description: command["description"] as? String,
                mode: command["mode"] as? String ?? "view"
            )
        }
        return StoreDetails(name: name, title: title, description: description, author: author, iconURL: iconURL, commands: commands)
    }

    static nonisolated func iconURL(for name: String, icon: Any?) -> URL? {
        guard let file = icon as? String, !file.isEmpty,
              !file.hasPrefix("icon:"), !file.hasPrefix("http"), !file.hasPrefix("data:") else { return nil }
        let fileName = file.split(separator: "/").last.map(String.init) ?? file
        // An installed copy has the file locally; otherwise fetch it, encoded (icon names may contain spaces).
        let local = Paths.extensions.appendingPathComponent(name).appendingPathComponent("assets").appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return URL(string: "\(rawBase)/\(name)/assets/\(encoded)")
    }

    // MARK: - Install machinery

    private struct FetchedExtension {
        let workDir: URL
        let extensionDir: URL
        let commit: String
    }

    private struct Record: Codable {
        let name: String
        let commit: String
        let installedAt: Date
    }

    private static func recordedCommit(for name: String) -> String? {
        let url = Paths.extensions
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(recordFileName)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        return record.commit
    }

    private static func fetchExtensionCopy(name: String) async throws -> FetchedExtension {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("floe-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let git = gitExecutable()
        let clone = ["clone", "--depth", "1", "--filter=blob:none", "--sparse", "https://github.com/raycast/extensions", workDir.path]
        try await runTool(executable: git, arguments: clone, context: String(localized: "Clone failed", bundle: .floe, comment: "What went wrong while installing an extension. Clone is the git operation."))
        let checkout = ["-C", workDir.path, "sparse-checkout", "set", "extensions/\(name)"]
        try await runTool(executable: git, arguments: checkout, context: String(localized: "Checkout failed", bundle: .floe, comment: "What went wrong while installing an extension. Checkout is the git operation."))
        let extensionDir = workDir.appendingPathComponent("extensions/\(name)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: extensionDir.appendingPathComponent("package.json").path) else {
            throw StoreFailure(message: String(localized: "Extension \"\(name)\" was not found in the Raycast repository.", bundle: .floe, comment: "The placeholder is an extension's name."))
        }
        let revision = ["-C", workDir.path, "rev-parse", "HEAD"]
        let output = try await runTool(executable: git, arguments: revision, context: String(localized: "Could not read the repository commit", bundle: .floe))
        let commit = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return FetchedExtension(workDir: workDir, extensionDir: extensionDir, commit: commit)
    }

    private static func runBunInstall(in directory: URL) async throws {
        guard let bun = Paths.bun else {
            throw StoreFailure(message: String(localized: "Bun was not found. Install it with brew install bun.", bundle: .floe, comment: "Bun is the name of a tool. brew install bun is a command and stays as written."))
        }
        try await runTool(executable: bun, arguments: ["install", "--ignore-scripts"], workingDirectory: directory, context: String(localized: "Bun install failed", bundle: .floe, comment: "What went wrong while installing an extension. Bun is the name of a tool."))
    }

    /// Moves the staged copy into the extensions folder only after its
    /// install succeeded. The previous copy is kept aside until the swap lands.
    private static func swapIn(name: String, staged: URL, commit: String) throws {
        Paths.prepareSupportFolders()
        let fileManager = FileManager.default
        let destination = Paths.extensions.appendingPathComponent(name, isDirectory: true)
        let backup = Paths.extensions.appendingPathComponent("\(name).floe-backup-\(UUID().uuidString)", isDirectory: true)
        var movedAside = false
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: destination, to: backup)
                movedAside = true
            }
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            if movedAside, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw StoreFailure(message: String(localized: "Could not install \"\(name)\": \(lastLine(error.localizedDescription))", bundle: .floe, comment: "The first placeholder is an extension's name, the second is the reason."))
        }
        if movedAside {
            try? fileManager.removeItem(at: backup)
        }
        let record = Record(name: name, commit: commit, installedAt: Date())
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: destination.appendingPathComponent(recordFileName), options: .atomic)
        }
    }

    private static func gitExecutable() -> String {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/git") {
            return "/usr/bin/git"
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for folder in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent("git").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/usr/bin/git"
    }

    struct ToolOutput {
        let stdout: String
        let stderr: String
    }

    struct StoreFailure: Error {
        let message: String
    }

    private static nonisolated func lastLine(_ text: String) -> String {
        text.split(separator: "\n").map(String.init).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? String(localized: "Unknown error", bundle: .floe)
    }

    /// How much of a tool's output is kept; git and bun say far less than this.
    private static let outputLimit = 4 * 1024 * 1024

    /// Runs a tool off the main thread. Failures carry the last stderr line.
    @concurrent @discardableResult
    static nonisolated func runTool(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        context: String
    ) async throws -> ToolOutput {
        do {
            let result = try await Subprocess.run(
                .path(FilePath(executable)),
                arguments: Arguments(arguments),
                workingDirectory: workingDirectory.map { FilePath($0.path) },
                output: .string(limit: outputLimit),
                error: .string(limit: outputLimit)
            )
            let stdout = result.standardOutput
            let stderr = result.standardError
            guard result.terminationStatus.isSuccess else {
                throw StoreFailure(message: String(localized: "\(context): \(lastLine(stderr.isEmpty ? stdout : stderr))", bundle: .floe, comment: "The first placeholder says what failed, the second is the reason."))
            }
            return ToolOutput(stdout: stdout, stderr: stderr)
        } catch let failure as StoreFailure {
            throw failure
        } catch {
            throw StoreFailure(message: String(localized: "\(context): \(error.localizedDescription)", bundle: .floe, comment: "The first placeholder says what failed, the second is the reason."))
        }
    }
}
