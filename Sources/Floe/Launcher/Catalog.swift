//
//  Catalog.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import AsyncAlgorithms

nonisolated enum Paths {
    /// The checkout this binary was built from, or `FLOE_ROOT`. Only used when running unbundled (`swift run`)
    /// or when the override is set, so an installed app never depends on it.
    private static let checkout: URL = {
        if let override = ProcessInfo.processInfo.environment["FLOE_ROOT"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }()

    /// The runtime copied into the app at build time, when there is one.
    private static let bundledRuntime: URL? = Bundle.main.resourceURL
        .map { $0.appendingPathComponent("runtime") }
        .flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("host.ts").path) ? $0 : nil }

    static let isDevelopment = ProcessInfo.processInfo.environment["FLOE_ROOT"] != nil || bundledRuntime == nil

    /// The bundled runtime, or the checkout's in development and when the bundle has none.
    static let runtime: URL = {
        if !isDevelopment, let bundledRuntime {
            return bundledRuntime
        }
        return checkout.appendingPathComponent("runtime")
    }()

    static let host = runtime.appendingPathComponent("host.ts")

    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Floe")
    /// Where builds from before the rename to Floe kept everything.
    private static let legacySupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LauncherProto")
    /// Extensions the user added.
    static let extensions = support.appendingPathComponent("Extensions")
    /// Per-extension storage, preferences and build cache, by extension name.
    static let data = support.appendingPathComponent("Data")
    /// Raycast-compatible script commands.
    static let scripts = support.appendingPathComponent("Scripts")

    /// Creates the support folders. Earlier builds kept per-extension data in "extensions", which on a
    /// case-insensitive volume is the same folder as "Extensions", so that data moves to "Data" first.
    static func prepareSupportFolders() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: support.path), fileManager.fileExists(atPath: legacySupport.path) {
            try? fileManager.moveItem(at: legacySupport, to: support)
        }
        let names = (try? fileManager.contentsOfDirectory(atPath: support.path)) ?? []
        if !names.contains("Data"), names.contains("extensions") {
            try? fileManager.moveItem(at: support.appendingPathComponent("extensions"), to: data)
        }
        try? fileManager.createDirectory(at: data, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: extensions, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
    }

    /// The checkout's sample extensions, listed only while developing.
    static let developmentExtensions: URL? = isDevelopment ? checkout.appendingPathComponent("extensions") : nil
    /// Extensions the Raycast app has installed. Read-only: builds and storage go to our own support folder.
    static let raycastExtensions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/raycast/extensions")

    /// The Bun shipped inside the app, else `FLOE_BUN`, else the first one on PATH (for `swift run`).
    static let bun: String? = {
        let environment = ProcessInfo.processInfo.environment
        let onPath = (environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("bun").path }
        return ([runtime.appendingPathComponent("bin/bun").path, environment["FLOE_BUN"]].compactMap(\.self) + onPath)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static var isBunBundled: Bool {
        bun == runtime.appendingPathComponent("bin/bun").path
    }
}

nonisolated extension AppEntry {
    /// The system, local and user Applications folders, each with its Utilities subfolder.
    static let folders: [String] = FileManager.default
        .urls(for: .applicationDirectory, in: [.localDomainMask, .systemDomainMask, .userDomainMask])
        .flatMap { [$0.path, $0.appendingPathComponent("Utilities").path] }

    static func scan() -> [AppEntry] {
        let found = folders.flatMap { folder -> [AppEntry] in
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            return entries.filter { $0.hasSuffix(".app") }.map { entry in
                let url = URL(fileURLWithPath: folder).appendingPathComponent(entry)
                let shown = FileManager.default.displayName(atPath: url.path)
                // Only a trailing ".app" goes: one in the middle of a name is part of it, as "Foo.app Maker" keeps.
                return AppEntry(name: shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown, url: url)
            }
        }
        // Safari lives in the cryptex and shows up again in /Applications; one entry per app name.
        return found.uniqued(on: \.name).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

nonisolated extension ExtensionCommand {
    /// Local extensions first, then Raycast's; an extension found in both is taken from the local copy.
    static func scan(includeRaycast: Bool = true) -> [ExtensionCommand] {
        Paths.prepareSupportFolders()
        let roots: [(URL, Source)] = [(Paths.extensions, .local)]
            + (Paths.developmentExtensions.map { [($0, .local)] } ?? [])
            + (includeRaycast ? [(Paths.raycastExtensions, .raycast)] : [])
        return Array(roots.flatMap { scan(root: $0.0, source: $0.1) }.uniqued(on: \.id))
    }

    /// Every runnable command under a folder of extensions, one subfolder per extension.
    static func scan(root: URL, source: Source) -> [ExtensionCommand] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { folder -> [ExtensionCommand] in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("package.json")) else { return [] }
            return commands(inManifest: data, folder: folder, source: source)
        }
    }
}

nonisolated extension CatalogSnapshot {
    /// A catalog scanned on the spot, for the diagnostic modes that print or render one state and
    /// exit. The GUI never uses this: its model starts empty and fills from the worker.
    static func scanningNow(includeRaycast: Bool) -> CatalogSnapshot {
        let scripts = ScriptCommand.scan()
        return CatalogSnapshot(
            apps: AppEntry.scan(),
            commands: ExtensionCommand.scan(includeRaycast: includeRaycast),
            scripts: scripts.commands,
            scriptFailures: scripts.failures,
            settingsPanes: SystemSettingsPane.scan(),
            sshHosts: SSHConfig.hosts(files: .user)
        )
    }
}

/// Watches the application folders and reports changes, so newly installed apps show up without a restart.
final class AppFolderWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let changes = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private var settling: Task<Void, Never>?

    init(onChange: @escaping @MainActor () -> Void) {
        let stream = changes.stream
        // Installers touch the folder several times; react once things settle.
        settling = Task { @MainActor in
            for await _ in stream.debounce(for: .seconds(1)) {
                onChange()
            }
        }
        for folder in AppEntry.folders {
            let descriptor = open(folder, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [continuation = changes.continuation] in
                continuation.yield()
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        settling?.cancel()
        changes.continuation.finish()
        sources.forEach { $0.cancel() }
    }
}
