//
//  ExtensionStore+Details.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What the store shows of one extension: its manifest and its icon, each read from the repository once.
extension ExtensionStore {
    /// The details once they are known, asked for once however many views want them. With `delay`, nothing is
    /// asked when the caller is cancelled first, which is what a row that left the screen does.
    func details(for name: String, after delay: Duration? = nil) async -> StoreDetails? {
        if let cached = detailsCache[name] {
            return cached
        }
        if let delay, detailsTasks[name] == nil {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return nil }
        }
        if let running = detailsTasks[name] {
            return await running.value
        }
        guard let url = URL(string: "\(Self.rawBase)/\(name)/package.json") else { return nil }
        let fetch = fetch
        let task = Task { await Self.loadDetails(name: name, from: url, fetch: fetch) }
        detailsTasks[name] = task
        let parsed = await task.value
        detailsTasks[name] = nil
        if let parsed {
            detailsCache[name] = parsed
        }
        return parsed
    }

    /// Where an icon is on this Mac: an installed copy's own file, or one fetched once and kept in the temporary folder.
    func iconFile(for url: URL) async -> String? {
        if let known = knownIconFile(for: url) {
            return known
        }
        let file = iconFolder.appendingPathComponent(Self.iconFileName(for: url))
        if FileManager.default.fileExists(atPath: file.path) {
            iconFiles[url] = file.path
            return file.path
        }
        if let running = iconTasks[url] {
            return await running.value
        }
        let fetch = fetch
        let task = Task { await Self.saveIcon(from: url, to: file, fetch: fetch) }
        iconTasks[url] = task
        let path = await task.value
        iconTasks[url] = nil
        iconFiles[url] = path
        return path
    }

    /// An icon's file when no waiting is needed for it, so a row that comes back draws it in the same pass.
    func knownIconFile(for url: URL) -> String? {
        url.isFileURL ? url.path : iconFiles[url]
    }

    /// Reads and parses a manifest off the main thread.
    @concurrent
    private static nonisolated func loadDetails(name: String, from url: URL, fetch: @Sendable (URL) async throws -> Data) async -> StoreDetails? {
        guard let data = try? await fetch(url),
              let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parseDetails(name: name, manifest: manifest)
    }

    @concurrent
    private static nonisolated func saveIcon(from url: URL, to file: URL, fetch: @Sendable (URL) async throws -> Data) async -> String? {
        guard let data = try? await fetch(url) else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: file, options: .atomic)) == nil ? nil : file.path
    }

    /// One name per icon of the repository: the extension's folder and the file, with nothing a path would read as a folder.
    static nonisolated func iconFileName(for url: URL) -> String {
        url.pathComponents.suffix(3).filter { $0 != "assets" }.joined(separator: "-")
    }

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
}
