//
//  ExtensionStore+Install.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Subprocess
import System

/// How a copy of an extension gets onto this Mac: fetched with git, installed with Bun, then swapped in.
extension ExtensionStore {
    struct FetchedExtension {
        let workDir: URL
        let extensionDir: URL
        let commit: String
    }

    struct Record: Codable {
        let name: String
        let commit: String
        let installedAt: Date
    }

    static func recordedCommit(for name: String) -> String? {
        let url = Paths.extensions
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(recordFileName)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        return record.commit
    }

    static func fetchExtensionCopy(name: String) async throws -> FetchedExtension {
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

    static func runBunInstall(in directory: URL) async throws {
        guard let bun = Paths.bun else {
            throw StoreFailure(message: String(localized: "Bun was not found. Install it with brew install bun.", bundle: .floe, comment: "Bun is the name of a tool. brew install bun is a command and stays as written."))
        }
        try await runTool(executable: bun, arguments: ["install", "--ignore-scripts"], workingDirectory: directory, context: String(localized: "Bun install failed", bundle: .floe, comment: "What went wrong while installing an extension. Bun is the name of a tool."))
    }

    /// Moves the staged copy into the extensions folder only after its
    /// install succeeded. The previous copy is kept aside until the swap lands.
    static func swapIn(name: String, staged: URL, commit: String) throws {
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
