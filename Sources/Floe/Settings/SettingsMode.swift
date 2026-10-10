//
//  SettingsMode.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// `Floe --settings`: the settings window in a process of its own, which ends when the window closes.
/// It is the same executable, so the defaults, the Keychain items and the permissions are the app's own.
enum SettingsMode {
    static func run(_ options: DebugOptions) -> Never {
        let app = NSApplication.shared
        let delegate = SettingsAppDelegate(page: options.settingsPage)
        app.delegate = delegate
        // The AI section names the tool found on the login shell's PATH.
        Task { await LoginEnvironment.load() }
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}

/// When the settings process may end: its window is closed and nothing it started is still going.
enum SettingsExit {
    static func isDue(windowOpen: Bool, otherWindowOpen: Bool, installing: Bool) -> Bool {
        !windowOpen && !otherWindowOpen && !installing
    }
}

final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let catalog = SettingsCatalog()
    private lazy var window = SettingsWindowController(catalog: catalog)
    private let launcherPid = getppid()
    private lazy var link = ProcessLink(role: .settings, gate: LinkGate(ownPid: getpid()) { [launcherPid] in launcherPid })
    private let startPage: SettingsPage?
    private var appWatcher: AppFolderWatcher?
    private var launcherWatch: DispatchSourceProcess?
    private var terminationWatch: DispatchSourceSignal?
    private var cancellables = Set<AnyCancellable>()

    init(page: SettingsPage?) {
        startPage = page
    }

    func applicationDidFinishLaunching(_: Notification) {
        // A regular app while its window is open: a Dock icon, and a menu bar with the Edit menu.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make(target: self, about: #selector(openAbout), settings: #selector(openSettings))
        endWithLauncher()
        connect()
        catalog.reloadAll()
        appWatcher = AppFolderWatcher { [weak self] in self?.catalog.reloadApps() }
        window.onClose = { [weak self] in self?.endIfDue() }
        window.show(page: startPage)
        link.send(.ready)
        // FLOE_SETTINGS_CLOSE_AFTER=<seconds> closes the window by itself, to check that the process ends with it.
        if let delay = ProcessInfo.processInfo.environment["FLOE_SETTINGS_CLOSE_AFTER"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.window.close() }
        }
    }

    /// Everything that crosses to the launcher, and everything taken from it.
    private func connect() {
        let link = link
        ProcessLink.current = link
        link.handler = { [weak self] in self?.handle($0) }
        link.start()

        settings.onSaved = { link.send(.settingsChanged) }
        SnippetStore.shared.onSaved = { link.send(.storeChanged(.snippets)) }
        QuicklinkStore.shared.onSaved = { link.send(.storeChanged(.quicklinks)) }
        PreferenceStore.onSaved = { link.send(.storeChanged(.preferences)) }
        settings.$isRecordingHotkey.removeDuplicates().dropFirst()
            .sink { link.send(.recording($0)) }
            .store(in: &cancellables)
        settings.$includeRaycastExtensions.removeDuplicates().dropFirst()
            // After the publisher's willSet, so the scan reads the new value.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.catalog.reloadCommands() }
            .store(in: &cancellables)
        window.selection.$page.removeDuplicates().dropFirst()
            .sink { link.send(LinkMessage(.pageChanged, $0.id)) }
            .store(in: &cancellables)

        // No updater here: Sparkle runs in the launcher, which is asked instead.
        UpdatesManager.shared.sendToLauncher = { [launcherPid] request in
            if request == .check, let launcher = NSRunningApplication(processIdentifier: launcherPid) {
                // Sparkle's window belongs to the launcher, which may only come forward if this app lets it.
                NSApp.yieldActivation(to: launcher)
            }
            link.send(LinkMessage(.updates, request.text))
        }
        ExtensionStore.shared.onInstalled = { [weak self] in
            self?.catalog.reloadCommands()
            link.send(.rescan(.commands))
        }
        ExtensionStore.shared.$busy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.endIfDue() }
            .store(in: &cancellables)
        OnboardingWindowController.shared.onClose = { [weak self] in self?.endIfDue() }
        ReadingWindow.onClose = { [weak self] in self?.endIfDue() }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:_:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    private func handle(_ message: LinkMessage) {
        switch message.kind {
        case .settingsChanged:
            settings.reload()
        case .storeChanged:
            reload(message.store)
        case .showPage:
            window.show(page: SettingsPage(id: message.payload))
        case .updatesState:
            if let state = UpdatesState(text: message.payload) {
                UpdatesManager.shared.show(state)
            }
        case .thawStatus:
            if let status = ThawAppearanceFollower.Status(rawValue: message.payload) {
                ThawAppearanceFollower.shared.mirror(status)
            }
        case .fileIndexState:
            FileIndexStatus.shared.state = FileIndexService.State(text: message.payload)
        case .syncState:
            SettingsSyncStatus.shared.status = SyncStatus(text: message.payload) ?? SyncStatus()
        default:
            break
        }
    }

    private func reload(_ store: LinkStore?) {
        switch store {
        case .snippets: SnippetStore.shared.reload()
        case .quicklinks: QuicklinkStore.shared.reload()
        case .preferences, nil: break
        }
    }

    /// The launcher ends this process when it quits. If the launcher dies instead, this notices.
    private func endWithLauncher() {
        let watch = DispatchSource.makeProcessSource(identifier: launcherPid, eventMask: .exit, queue: .main)
        watch.setEventHandler { [weak self] in self?.end() }
        watch.resume()
        launcherWatch = watch
        // SIGTERM is how the launcher ends it: taken here so an edit made a moment ago is still saved.
        // An empty handler and not SIG_IGN, which the tools the Extension Store runs would inherit.
        signal(SIGTERM) { _ in
            // The signal source below acts on it.
        }
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { [weak self] in self?.end() }
        termination.resume()
        terminationWatch = termination
    }

    /// Ends the process once the window is closed, unless a window opened from it (the welcome,
    /// the release notes, the acknowledgements) is still up or an install it started is still going.
    private func endIfDue() {
        let otherWindowOpen = OnboardingWindowController.shared.isOpen || ReadingWindow.isAnyOpen
        let installing = !ExtensionStore.shared.busy.isEmpty
        if SettingsExit.isDue(windowOpen: window.isOpen, otherWindowOpen: otherWindowOpen, installing: installing) {
            end()
        }
    }

    private func end() -> Never {
        // The debounced save may still be waiting.
        if settings.hasUnsavedChanges {
            settings.save()
        }
        exit(0)
    }

    @objc private func openAbout() {
        window.show(page: .about)
    }

    @objc private func openSettings() {
        window.show()
    }

    /// A click on the Dock icon brings the window back, also while only an install keeps the process alive.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        window.show()
        return false
    }

    /// Scripts and extensions are added in Finder too, so coming back to Settings looks again.
    func applicationDidBecomeActive(_: Notification) {
        catalog.reloadCommands()
        catalog.reloadScripts()
    }

    /// Quit in this process quits Floe, as it did when Settings was one of the launcher's windows.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        link.send(.quit)
        return .terminateNow
    }

    func applicationWillTerminate(_: Notification) {
        if settings.hasUnsavedChanges {
            settings.save()
        }
    }

    /// The launcher handles `floe://` links. If the system hands Thaw's answer to this process, it is passed on.
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor?, _: NSAppleEventDescriptor?) {
        guard let text = event?.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text),
              url.scheme?.lowercased() == "floe", url.host?.lowercased() == ThawAppearanceFollower.callbackHost
        else { return }
        link.send(LinkMessage(.forwardURL, text))
    }
}
