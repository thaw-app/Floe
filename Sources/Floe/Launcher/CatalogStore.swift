//
//  CatalogStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What this Mac has to search and list: apps, extension commands, scripts, System Settings' panes and SSH hosts.
/// Each part is scanned off the main thread, and a scan overtaken by a newer one is dropped. The launcher and the
/// settings window each keep one.
final class CatalogStore: ObservableObject {
    enum Part {
        case apps, commands, scripts, settingsPanes, sshHosts
    }

    @Published private(set) var apps: [AppEntry] = []
    /// Every command found, including those of disabled extensions; the settings window lists these.
    @Published private(set) var allCommands: [ExtensionCommand] = []
    /// Every script command found in the Scripts folder.
    @Published private(set) var allScripts: [ScriptCommand] = []
    /// Files in the Scripts folder that failed to parse, for the settings pane.
    @Published private(set) var scriptFailures: [ScriptFailure] = []
    /// True until apps, commands and scripts have each been scanned once, and while one of them is scanned again.
    @Published private(set) var isLoading = true
    /// System Settings' panes, found once at launch: they only change with the system.
    private(set) var settingsPanes: [SystemSettingsPane] = []
    /// The hosts of the SSH configuration.
    private(set) var sshHosts: [SSHHost] = []

    /// Told which part changed, after it is published.
    var onChange: (Part) -> Void = { _ in }

    private let scanner: any CatalogScanning
    private let settings: AppSettings
    /// Numbers each part's requests, so only the answer to the newest one is published.
    private var latest: [Part: Int] = [:]
    /// The parts scanned at least once. The catalog is loading until apps, commands and scripts are.
    private var loaded: Set<Part> = []
    private var commandsTask: Task<Void, Never>?
    private var scriptsTask: Task<Void, Never>?

    /// With a snapshot the catalog is complete at once, for tests and the modes that draw one state and exit.
    init(scanner: any CatalogScanning = CatalogLoader(), settings: AppSettings = .shared, snapshot: CatalogSnapshot? = nil) {
        self.scanner = scanner
        self.settings = settings
        guard let snapshot else { return }
        apps = snapshot.apps
        allCommands = snapshot.commands
        allScripts = snapshot.scripts
        scriptFailures = snapshot.scriptFailures
        settingsPanes = snapshot.settingsPanes
        sshHosts = snapshot.sshHosts
        loaded = [.apps, .commands, .scripts]
        isLoading = false
    }

    func reloadAll() {
        reloadApps()
        reloadCommands()
        reloadScripts()
    }

    func reloadApps() {
        let generation = begin(.apps)
        Task { @concurrent [weak self, scanner] in
            let apps = await scanner.scanApps()
            await self?.finish(generation: generation, apps: apps)
        }
    }

    func reloadCommands() {
        let generation = begin(.commands)
        // Read once, here: the worker never sees the mutable settings object.
        let includeRaycast = settings.includeRaycastExtensions
        commandsTask = Task { @concurrent [weak self, scanner] in
            let commands = await scanner.scanCommands(includeRaycast: includeRaycast)
            await self?.finish(generation: generation, commands: commands)
        }
    }

    func reloadScripts() {
        let generation = begin(.scripts)
        scriptsTask = Task { @concurrent [weak self, scanner] in
            let scan = await scanner.scanScripts()
            await self?.finish(generation: generation, scripts: scan)
        }
    }

    func reloadSettingsPanes() {
        Task { @concurrent [weak self, scanner] in
            let panes = await scanner.scanSettingsPanes()
            await self?.finish(settingsPanes: panes)
        }
    }

    @discardableResult
    func reloadSSHHosts() -> Task<Void, Never> {
        Task { @concurrent [weak self, scanner] in
            let hosts = await scanner.scanSSHHosts()
            await self?.finish(sshHosts: hosts)
        }
    }

    /// Joins the command scan in flight, following any newer request that replaces it while the caller waits.
    /// Results are published before the joined task finishes, so a caller that returns sees the current catalog.
    @MainActor
    func waitForCommands() async {
        while let task = commandsTask {
            await task.value
        }
    }

    /// Joins the script scan in flight, following any newer request that replaces it while the caller waits.
    @MainActor
    func waitForScripts() async {
        while let task = scriptsTask {
            await task.value
        }
    }

    // MARK: Publishing

    @MainActor
    private func finish(generation: Int, apps newApps: [AppEntry]) {
        guard isLatest(generation, of: .apps) else { return }
        markLoaded(.apps)
        apps = newApps
        Log.catalog.info("Applications scanned: \(newApps.count)")
        onChange(.apps)
    }

    @MainActor
    private func finish(generation: Int, commands newCommands: [ExtensionCommand]) {
        guard isLatest(generation, of: .commands) else { return }
        commandsTask = nil
        markLoaded(.commands)
        allCommands = newCommands
        Log.catalog.info("Extension commands scanned: \(newCommands.count)")
        onChange(.commands)
    }

    @MainActor
    private func finish(generation: Int, scripts scan: ScriptScan) {
        guard isLatest(generation, of: .scripts) else { return }
        scriptsTask = nil
        // The folder is scanned each time the panel opens and is nearly always the same: then nothing changes.
        let isSame = loaded.contains(.scripts) && scan.commands == allScripts && scan.failures == scriptFailures
        markLoaded(.scripts)
        guard !isSame else { return }
        allScripts = scan.commands
        scriptFailures = scan.failures
        onChange(.scripts)
    }

    @MainActor
    private func finish(settingsPanes panes: [SystemSettingsPane]) {
        settingsPanes = panes
        onChange(.settingsPanes)
    }

    @MainActor
    private func finish(sshHosts hosts: [SSHHost]) {
        guard hosts != sshHosts else { return }
        sshHosts = hosts
        onChange(.sshHosts)
    }

    /// Starts a request for a part: the catalog is loading until it answers.
    private func begin(_ part: Part) -> Int {
        latest[part, default: 0] += 1
        isLoading = true
        return latest[part, default: 0]
    }

    private func isLatest(_ generation: Int, of part: Part) -> Bool {
        generation == latest[part]
    }

    private func markLoaded(_ part: Part) {
        loaded.insert(part)
        let loading = !loaded.isSuperset(of: [.apps, .commands, .scripts])
        if loading != isLoading {
            isLoading = loading
        }
    }
}
