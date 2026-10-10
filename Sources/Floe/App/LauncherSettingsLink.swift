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
    private let settings: AppSettings
    private let hotkeys: HotkeyRegistry
    private let process = SettingsProcess()
    private let link: ProcessLink
    private var recording = RemoteRecording()
    private lazy var sync = SettingsSyncService(settings: settings, extensions: extensionSync)
    private lazy var extensionSync = ExtensionSettingsSync(
        access: .stored(includes: { [settings] in settings.syncsExtensionSettings }, commands: { [model] in model.allCommands }),
        storage: .file(Paths.support.appendingPathComponent("ExtensionSync.json"))
    )
    private var cancellables = Set<AnyCancellable>()

    init(model: LauncherModel, settings: AppSettings = .shared, hotkeys: HotkeyRegistry) {
        self.model = model
        self.settings = settings
        self.hotkeys = hotkeys
        let process = process
        link = ProcessLink(role: .launcher, gate: LinkGate(ownPid: getpid()) { process.pid })
    }

    func start() {
        let link = link
        ProcessLink.current = link
        link.handler = { [weak self] in self?.handle($0) }
        link.start()

        settings.onSaved = { link.send(.settingsChanged) }
        SnippetStore.shared.onSaved = { link.send(.storeChanged(.snippets)) }
        QuicklinkStore.shared.onSaved = { link.send(.storeChanged(.quicklinks)) }
        let sync = sync
        PreferenceStore.onSaved = { sync.extensionSettingsChanged() }
        // An extension installed after its record arrived takes the record once the scan lists it.
        model.$allCommands.dropFirst()
            .sink { _ in sync.extensionSettingsChanged() }
            .store(in: &cancellables)
        ThawAppearanceFollower.shared.$status
            // After the publisher's willSet, and after the answer it stands for is in the defaults.
            .receive(on: DispatchQueue.main)
            .sink { link.send(LinkMessage(.thawStatus, $0.rawValue)) }
            .store(in: &cancellables)
        // The index of file names follows its switch from here on, and Settings is told how it is doing.
        settings.$indexesFileNames.removeDuplicates()
            .sink { isOn in
                FileIndexService.shared.set(on: isOn)
                // The order of the matches uses when files were last opened, which Spotlight knows.
                RecentFileUse.shared.follow(isOn)
            }
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

    func terminate() {
        process.terminate()
    }

    private func suspendHotkeys(local: Bool) {
        hotkeys.isSuspended = local || recording.isRecording
    }

    private func settingsProcessExited() {
        recording.settingsProcessExited()
        suspendHotkeys(local: settings.isRecordingHotkey)
        // Its last words may not have arrived, so everything it could have changed is read once more.
        settings.reload()
        SnippetStore.shared.reload()
        QuicklinkStore.shared.reload()
    }

    private func handle(_ message: LinkMessage) {
        switch message.kind {
        case .settingsChanged:
            settings.reload()
        case .storeChanged:
            reload(message.store)
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

    private func reload(_ store: LinkStore?) {
        switch store {
        case .snippets: SnippetStore.shared.reload()
        case .quicklinks: QuicklinkStore.shared.reload()
        case .preferences: sync.extensionSettingsChanged()
        case nil: break
        }
    }

    private func rescan(_ scan: LinkScan?) {
        switch scan {
        case .scripts: model.reloadScripts()
        case .commands: model.reloadCommands()
        case nil: break
        }
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
            ClipboardHistoryStore.shared.clear()
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
