//
//  KnownNoteFolders.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The folders of notes that apps on this Mac already keep, offered in Settings so the user need not find them.
enum KnownNoteFolders {
    struct Folder: Identifiable, Hashable {
        let app: String
        let path: String

        var id: String {
            path
        }

        /// "Obsidian: Documents", by the app and the folder's name.
        var title: String {
            "\(app): \((path as NSString).lastPathComponent)"
        }
    }

    /// Obsidian's vaults, from the list it keeps of them.
    static func obsidianVaults(in data: Data?) -> [String] {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = root["vaults"] as? [String: [String: Any]] else { return [] }
        return vaults.values.compactMap { $0["path"] as? String }.sorted()
    }

    /// Octarine's workspaces, from the table it keeps of them. Read with the system's sqlite3, without opening the app.
    static func octarineWorkspaces(database: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        let sqlite = Process()
        sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqlite.arguments = ["-readonly", database.path, "select path from workspaces;"]
        let pipe = Pipe()
        sqlite.standardOutput = pipe
        sqlite.standardError = FileHandle.nullDevice
        guard (try? sqlite.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        sqlite.waitUntilExit()
        return (String(bytes: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline).map(String.init).filter { $0.hasPrefix("/") }.sorted()
    }

    /// Every folder an app keeps notes in that is still there.
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Folder] {
        let support = home.appendingPathComponent("Library/Application Support")
        let obsidian = obsidianVaults(in: try? Data(contentsOf: support.appendingPathComponent("obsidian/obsidian.json"))).map { Folder(app: "Obsidian", path: $0) }
        let octarine = octarineWorkspaces(database: support.appendingPathComponent("Octarine/octarine.sqlite")).map { Folder(app: "Octarine", path: $0) }
        return (obsidian + octarine).filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
