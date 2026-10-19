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
            if !parsed.runsOnMac {
                leaveOut(name)
            }
        }
        return parsed
    }

    /// Where an icon or a screenshot is on this Mac: an installed copy's own file, or one fetched once and kept in the temporary folder.
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

    /// The addresses of an extension's screenshots, listed once a session. Empty when GitHub cannot be asked,
    /// so a pane without them shows no strip and asks again only in the next session.
    func screenshots(for name: String) async -> [URL] {
        if let cached = screenshotsCache[name] {
            return cached
        }
        if let running = screenshotTasks[name] {
            return await running.value
        }
        guard let url = URL(string: "\(Self.repoAPI)/contents/extensions/\(name)/metadata") else { return [] }
        let fetch = fetch
        let task = Task { await Self.loadScreenshots(name: name, from: url, fetch: fetch) }
        screenshotTasks[name] = task
        let found = await task.value
        screenshotTasks[name] = nil
        screenshotsCache[name] = found
        return found
    }

    @concurrent
    private static nonisolated func loadScreenshots(name: String, from url: URL, fetch: @Sendable (URL) async throws -> Data) async -> [URL] {
        guard let data = try? await fetch(url) else { return [] }
        return screenshotURLs(name: name, listing: data)
    }

    /// The images in GitHub's listing of the metadata folder, by name, read from the same place as the icons.
    /// Anything that is not a list of files lists nothing.
    static nonisolated func screenshotURLs(name: String, listing: Data) -> [URL] {
        let images: Set = ["png", "jpg", "jpeg", "gif", "webp"]
        let entries = (try? JSONSerialization.jsonObject(with: listing)) as? [[String: Any]] ?? []
        return entries
            .filter { $0["type"] as? String == "file" }
            .compactMap { $0["name"] as? String }
            .filter { images.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { file in
                let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
                return URL(string: "\(rawBase)/\(name)/metadata/\(encoded)")
            }
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
        let forMac = (manifest["commands"] as? [[String: Any]] ?? []).filter { ExtensionCommand.runsOnMac($0["platforms"] as? [String]) }
        let commands = forMac.compactMap { command -> StoreCommand? in
            guard let commandName = command["name"] as? String else { return nil }
            let arguments = (command["arguments"] as? [[String: Any]] ?? []).compactMap { argument -> StoreArgument? in
                guard let argumentName = argument["name"] as? String else { return nil }
                return StoreArgument(name: argumentName, placeholder: argument["placeholder"] as? String)
            }
            return StoreCommand(
                name: commandName,
                title: command["title"] as? String ?? commandName,
                description: command["description"] as? String,
                mode: command["mode"] as? String ?? "view",
                iconURL: Self.iconURL(for: name, icon: command["icon"]),
                arguments: arguments
            )
        }
        var details = StoreDetails(name: name, title: title, description: description, author: author, iconURL: iconURL, commands: commands)
        details.runsOnMac = ExtensionCommand.runsOnMac(manifest["platforms"] as? [String])
        details.categories = manifest["categories"] as? [String] ?? []
        details.needsSetup = hasRequiredPreference(manifest) || forMac.contains(where: hasRequiredPreference)
        return details
    }

    private static nonisolated func hasRequiredPreference(_ owner: [String: Any]) -> Bool {
        (owner["preferences"] as? [[String: Any]] ?? []).contains { $0["required"] as? Bool == true }
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
