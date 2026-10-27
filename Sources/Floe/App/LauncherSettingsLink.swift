//
//  LauncherSettingsLink.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// The launcher's side of Settings: starts the settings process, tells it what changed here, and
/// does what it asks. The launcher builds no settings view of its own.
final class LauncherSettingsLink {
    private let model: LauncherModel
    private let clipboard: ClipboardHistoryStore
    private let settings: AppSettings
    private let hotkeys: HotkeyRegistry
    private let process = SettingsProcess()
    private let link: ProcessLink
    private var recording = RemoteRecording()
    private lazy var sync = SettingsSyncService(settings: settings, extensions: extensionSync)
    private lazy var extensionSync = ExtensionSettingsSync(
        access: .stored(includes: { [settings] in settings.syncsExtensionSettings }, commands: { [model] in model.catalog.allCommands }),
        storage: .file(Paths.support.appendingPathComponent("ExtensionSync.json"))
    )
    private var cancellables = Set<AnyCancellable>()
    /// After Settings changed something: the search reads it again.
    var onChange: (() -> Void)?

    /// Gates incoming Settings messages against the process this resident actually launched.
    init(model: LauncherModel, clipboard: ClipboardHistoryStore, settings: AppSettings = .shared, hotkeys: HotkeyRegistry) {
        self.clipboard = clipboard
        self.model = model
        self.settings = settings
        self.hotkeys = hotkeys
        let process = process
        link = ProcessLink(role: .launcher, gate: LinkGate(ownPid: getpid(), key: { process.key }, peerPid: { process.pid }))
    }

    /// Starts resident-owned synchronization and publishes service state to Settings.
    func start() {
        let link = link
        ProcessLink.current = link
        link.handler = { [weak self] in self?.handle($0) }
        link.start()

        let sync = sync
        SharedStores.announceSaves(settings: settings, preferencesSaved: { sync.extensionSettingsChanged() }, send: link.send)
        // An extension installed after its record arrived takes the record once the scan lists it.
        model.catalog.$allCommands.dropFirst()
            .sink { _ in sync.extensionSettingsChanged() }
            .store(in: &cancellables)
        ThawAppearanceFollower.shared.$status
            // After the publisher's willSet, and after the answer it stands for is in the defaults.
            .receive(on: DispatchQueue.main)
            .sink { link.send(LinkMessage(.thawStatus, $0.rawValue)) }
            .store(in: &cancellables)
        // The index of file names follows its switch from here on, and Settings is told how it is doing.
        settings.$indexesFileNames.removeDuplicates()
            .sink { FileIndexService.shared.set(on: $0) }
            .store(in: &cancellables)
        FileIndexService.shared.observe { link.send(LinkMessage(.fileIndexState, $0.text)) }
        sync.start { link.send(LinkMessage(.syncState, $0.text)) }
        // Without push, another Mac's changes arrive when the panel opens.
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .filter { $0.object is LauncherPanel }
            .sink { _ in sync.look() }
            .store(in: &cancellables)
        if UpdatesManager.shared.isAvailable {
            UpdatesManager.shared.observeState { link.send(LinkMessage(.updatesState, UpdatesManager.shared.state.text)) }
        }
        settings.$isRecordingHotkey
            .sink { [weak self] isRecording in self?.suspendHotkeys(local: isRecording) }
            .store(in: &cancellables)

        process.bringForward = { link.send(LinkMessage(.showPage, $0)) }
        process.onExit = { [weak self] in self?.settingsProcessExited() }
    }

    /// Opens Settings, on a page if one is named by its `SettingsPage.id`.
    func show(page: String? = nil) {
        sync.look(always: true)
        process.show(page: page)
    }

    /// Ends the owned Settings process during resident shutdown.
    func terminate() {
        process.terminate()
    }

    /// Suppresses global shortcuts while either process is recording a new shortcut.
    private func suspendHotkeys(local: Bool) {
        hotkeys.isSuspended = local || recording.isRecording
    }

    /// Clears remote recording state and reloads stores even if the final notification was lost.
    private func settingsProcessExited() {
        recording.settingsProcessExited()
        suspendHotkeys(local: settings.isRecordingHotkey)
        // Its last words may not have arrived, so everything it could have changed is read once more.
        settings.reload()
        SnippetStore.shared.reload()
        QuicklinkStore.shared.reload()
    }

    /// Applies a validated Settings message, then has the search read it again.
    private func handle(_ message: LinkMessage) {
        defer { onChange?() }
        switch message.kind {
        case .settingsChanged:
            settings.reload()
        case .storeChanged:
            SharedStores.reload(message.store) { [sync] in sync.extensionSettingsChanged() }
        case .ready:
            // A process just started has its window up by now.
            process.activate()
            link.send(LinkMessage(.thawStatus, ThawAppearanceFollower.shared.status.rawValue))
            link.send(LinkMessage(.updatesState, UpdatesManager.shared.state.text))
            link.send(LinkMessage(.fileIndexState, FileIndexService.shared.state.text))
            link.send(LinkMessage(.syncState, sync.engine.status.text))
        case .pageChanged:
            process.lastPage = message.payload
        case .recording:
            recording.received(message.isRecording)
            suspendHotkeys(local: settings.isRecordingHotkey)
        default:
            perform(message)
        }
    }

    /// Refreshes the command or script catalog requested by Settings.
    private func rescan(_ scan: LinkScan?) {
        guard let scan else { return }
        model.catalog.reload(scan)
    }

    /// The things Settings has the launcher do, because what they act on lives here.
    private func perform(_ message: LinkMessage) {
        switch message.kind {
        case .updates:
            if let request = UpdateRequest(text: message.payload) {
                UpdatesManager.shared.perform(request)
            }
        case .rescan:
            rescan(message.scan)
        case .clearClipboardHistory:
            clipboard.clear()
        case .removeSyncedSettings:
            sync.engine.removeFromCloud()
        case .forwardURL:
            if let url = URL(string: message.payload) {
                IncomingURLRouter.shared.route(url)
            }
        case .quit:
            NSApp.terminate(nil)
        default:
            break
        }
    }
}

extension CatalogStore {
    func reload(_ scan: LinkScan) {
        switch scan {
        case .scripts: reloadScripts()
        case .commands: reloadCommands()
        }
    }
}
