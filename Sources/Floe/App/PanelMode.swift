//
//  PanelMode.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine
import SwiftUI

/// Same signed executable, but no hotkeys, clipboard recorder, background extensions or updater.
/// EOF on its private input pipe ends it even when the resident crashed.
enum PanelMode {
    /// Installs forwarding before creating the model, then runs until shutdown or parent EOF.
    static func run() -> Never {
        let channel = PanelChannel(input: .standardInput, output: .standardOutput)
        UsageStore.shared.forwardUse = { channel.send(.used($0)) }
        UsageStore.shared.forwardQuery = { channel.send(.query($0)) }
        let app = NSApplication.shared
        let delegate = PanelAppDelegate(channel: channel)
        app.delegate = delegate
        Task { await LoginEnvironment.load() }
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}

/// How long the closed launcher's process waits for the next open, which then draws in milliseconds
/// instead of starting the process over.
nonisolated enum PanelKeepAlive {
    static let closed: TimeInterval = 180
    /// Under memory pressure, and in the resident benchmark, the process goes as soon as it is idle.
    static let brief: TimeInterval = 0.75

    static func wait(underPressure: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval {
        underPressure || environment["FLOE_RESIDENT_BENCH"] != nil ? brief : closed
    }
}

final class PanelAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: LauncherModel
    let channel: PanelChannel
    /// The resident's clipboard history, read again when it says it saved; changes are sent to it.
    private let clipboard: ClipboardHistoryStore
    private let settings = AppSettings.shared
    private lazy var onboarding = OnboardingWindowController(settings: settings, permissions: .shared)
    /// The floating note lives here, beside the launcher: a visible window keeps this process from going idle.
    private lazy var floatingNote = FloatingNoteWindowController(settings: settings) { [weak self] in self?.model.record($0) }
    private var panel: LauncherPanel?
    private var keyMonitor: Any?
    private var appWatcher: AppFolderWatcher?
    private var timer: Timer?
    private var terminationWatch: DispatchSourceSignal?
    private var pressureWatch: DispatchSourceMemoryPressure?
    private var underPressure = false
    private var cancellables = Set<AnyCancellable>()
    private var sequence = 0
    private var lastActivity = Date()
    private var reportedIdle = false
    private var ending = false

    /// Uses the inherited pipe channel; no public IPC endpoint is opened by the foreground.
    init(channel: PanelChannel) {
        self.channel = channel
        clipboard = ClipboardHistoryStore(monitorsPasteboard: false, remote: { channel.send($0) })
        model = LauncherModel(clipboard: clipboard)
    }

    /// Wires foreground-only services and state mirrors before announcing readiness.
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(target: self, about: #selector(openAbout), settings: #selector(openSettings))
        Log.follow(settings).store(in: &cancellables)
        model.panelHost = PanelHost(
            hidePanel: { [weak self] in self?.hide() },
            showPanel: { [weak self] in self?.show() },
            showHUD: { ThawHUD.show(text: $0) },
            openSettings: { [weak self] page in
                self?.hide()
                self?.channel.send(.openSettings(page?.id))
            },
            residentRequests: { [channel] in channel.send($0) }
        )
        model.panelHost.showFloatingNote = { [weak self] in self?.floatingNote.show() }
        CommandLauncher.shared = .panel(model: model) { [channel] in channel.send($0) }
        model.canAskAI = AskAI.availabilityCheck { AIAnswer.isAvailable }
        model.typing.window = 0.03
        // A shell suggestion's snapshot arrived: rows read again, so they are there without another key.
        ShellSnapshots.shared.whenChanged { [weak self] in self?.model.refresh() }
        model.panelWindowSizes(settings: settings)
            .sink { [weak self] size in self?.panel?.resizeKeepingTop(to: size) }
            .store(in: &cancellables)
        followSearchSettings()
        AppPermissions.shared.onPermissionTransition = { [weak self] permission, granted in
            guard granted, permission === AppPermissions.shared.accessibility else { return }
            self?.model.accessibilityWasGranted()
        }
        SharedStores.announceSaves(settings: settings) { [channel] message in
            // The defaults reach the disk before the resident reads them again.
            if message.kind == .settingsChanged {
                CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            }
            channel.send(.settings(message.kind.rawValue, message.payload))
        }
        appWatcher = AppFolderWatcher { [weak self] in self?.model.catalog.reloadApps() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            return self.model.handlePanelKey(event, layout: self.settings.launcherLayout) ? nil : event
        }
        onboarding.openLauncher = { [weak self] in self?.show() }
        channel.receive = { [weak self] in self?.receive($0) }
        channel.onClose = { [weak self] in self?.end() }
        channel.start()
        watchTermination()
        watchMemoryPressure()
        model.startCatalogLoading()
        IntentHandler.current = .serving(model) { [channel] in channel.send(.present($0)) }
        IncomingURLRouter.shared.forwardAppearance = { [channel] in channel.send(.settings(LinkMessage.Kind.forwardURL.rawValue, $0.absoluteString)) }
        IncomingURLRouter.shared.install(followsAppearance: false)
        timer = Timer.scheduledOnMain(withTimeInterval: 0.25, repeats: true) { [weak self] in self?.reportIdleIfDue() }
        channel.send(.ready)
    }

    /// Keeps search-only recency and exchange-rate work out of the long-lived resident, and follows the Raycast switch.
    private func followSearchSettings() {
        model.followClipboardRole().store(in: &cancellables)
        settings.$indexesFileNames.removeDuplicates()
            .sink { isOn in
                FileIndexService.shared.set(on: isOn)
                // Only foreground searches use Spotlight's recency data; the resident just maintains names.
                RecentFileUse.shared.follow(isOn)
            }
            .store(in: &cancellables)
        settings.$fetchesExchangeRates.removeDuplicates()
            .sink { ExchangeRateUpdater.shared.set(on: $0) }
            .store(in: &cancellables)
        model.catalog.followRaycastSwitch().store(in: &cancellables)
    }

    /// Applies resident snapshots and records request sequences before performing user work.
    func receive(_ packet: PanelPacket) {
        switch packet {
        case let .request(request, sequence):
            self.sequence = sequence
            reportedIdle = false
            lastActivity = Date()
            perform(request)
        case .shutdown: end()
        case let .appearance(value):
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            if let status = ThawAppearanceFollower.Status(rawValue: value) {
                ThawAppearanceFollower.shared.mirror(status)
            }
        case .refresh: model.refresh()
        case .reload:
            SharedStores.reloadAll(settings: settings)
            model.refresh()
        case let .rescan(scan): model.catalog.reload(scan)
        case let .timers(timers):
            model.features.timers.running.mirror(timers)
            model.refresh()
        case let .clipboard(change):
            clipboard.apply(change)
        default: break
        }
    }

    /// Presents or dismisses the requested surface without bypassing the resident's lifecycle gate.
    private func perform(_ request: PanelRequest) {
        switch request {
        case .show: show()
        case .toggle:
            if panel?.isVisible == true {
                hide()
            } else {
                show()
            }
        case .hide: hide()
        case .onboarding:
            if !onboarding.showIfNeeded() {
                show()
            }
        case let .hud(text): ThawHUD.show(text: text)
        case let .url(url): IncomingURLRouter.shared.route(url)
        default: runCommand(request)
        }
    }

    /// Holds finite work alive while catalogs load, then resolves the requested command by ID.
    private func runCommand(_ request: PanelRequest) {
        switch request {
        case let .builtIn(key):
            if let item = LauncherModel.hotkeyItems.first(where: { $0.settingsKey == key }) {
                model.runFromHotkey(item)
            }
        case let .command(id, data, context):
            PanelWork.perform { [model] in
                await model.catalog.waitForCommands()
                guard let command = model.commands.first(where: { $0.id == id }) else { return }
                model.runner.run(command, arguments: CommandLauncher.object(data), context: CommandLauncher.object(context))
            }
        case let .script(id):
            PanelWork.perform { [model] in
                await model.catalog.waitForScripts()
                if let script = model.catalog.allScripts.first(where: { $0.id == id }) {
                    model.features.scripts.run(script)
                }
            }
        default: break
        }
    }

    /// Constructs the window only on first presentation; benchmarks render it offscreen.
    private func show() {
        if panel == nil {
            let created = LauncherPanel(size: model.panelState.windowSize(in: settings.launcherLayout))
            created.delegate = self
            created.contentView = NSHostingView(rootView: LauncherView(model: model).openingLinksInTheChosenBrowser())
            panel = created
        }
        guard let panel, !panel.isVisible || !panel.isKeyWindow else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(model.panelState.origin(in: frame, panelSize: panel.frame.size))
        }
        lastActivity = Date()
        model.panelWillShow()
        if ProcessInfo.processInfo.environment["FLOE_RESIDENT_BENCH"] != nil {
            panel.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            panel.orderFrontRegardless()
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        } else {
            panel.makeKeyAndOrderFront(nil)
            // Drawn and sent to the screen now, before the reloads below take their turn on the main thread.
            panel.displayIfNeeded()
            CATransaction.flush()
        }
        if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
            NSLog("Panel %d shown key=%d active=%d", getpid(), panel.isKeyWindow ? 1 : 0, NSApp.isActive ? 1 : 0)
        }
        model.focusToken += 1
        model.panelDidShow()
    }

    /// Dismisses the window and starts the idle grace period without canceling leased work.
    private func hide() {
        guard let panel, panel.isVisible else { return }
        if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
            NSLog("Panel %d hiding key=%d active=%d", getpid(), panel.isKeyWindow ? 1 : 0, NSApp.isActive ? 1 : 0)
        }
        panel.orderOut(nil)
        model.panelDidHide()
        lastActivity = Date()
    }

    /// Reports idle once per request only when no surface, modal interaction or finite work remains.
    private func reportIdleIfDue() {
        guard sequence > 0, !reportedIdle,
              Date().timeIntervalSince(lastActivity) >= PanelKeepAlive.wait(underPressure: underPressure),
              !PanelWork.isBusy, !ModalGuard.isActive,
              model.runner.session == nil, model.setup == nil,
              !onboarding.isOpen,
              !NSApp.windows.contains(where: \.isVisible)
        else { return }
        reportedIdle = true
        channel.send(.idle(sequence: sequence))
    }

    /// Defers dismissal so AppKit can finish transferring focus to any modal surface.
    func windowDidResignKey(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !ModalGuard.isActive, self.panel?.isKeyWindow == false else { return }
            if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
                NSLog("Panel %d resigned; front=%@", getpid(), NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")
            }
            self.hide()
        }
    }

    /// Handles SIGTERM on the main queue so settings and outgoing messages can finish first.
    private func watchTermination() {
        signal(SIGTERM, SIG_IGN)
        let watch = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        watch.setEventHandler { [weak self] in self?.end() }
        watch.resume()
        terminationWatch = watch
    }

    /// Once macOS asks for memory back, the closed launcher's process stops waiting for the next open.
    private func watchMemoryPressure() {
        let watch = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        watch.setEventHandler { [weak self] in self?.underPressure = true }
        watch.resume()
        pressureWatch = watch
    }

    /// Saves pending settings and drains outgoing mutations before ending the disposable process.
    private func end() {
        guard !ending else { return }
        ending = true
        timer?.invalidate()
        if settings.hasUnsavedChanges {
            settings.save()
        }
        model.runner.session?.forceStop()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        // The notes view's and the floating note's last edits are saved before the process goes.
        let deskSave = model.noteDeskSave
        Task { [floatingNote, channel] in
            _ = await deskSave?.value
            floatingNote.finish { channel.drain { exit(0) } }
        }
    }

    /// Asks the resident to open Settings on its remembered page after hiding the launcher.
    @objc private func openSettings() {
        hide(); channel.send(.openSettings(nil))
    }

    /// Routes About through the resident's separately owned Settings process.
    @objc private func openAbout() {
        hide(); channel.send(.openSettings(SettingsPage.about.id))
    }
}

/// Quitting and the Dock are the resident's to answer, so this process hands both on.
extension PanelAppDelegate {
    /// Quitting from a foreground menu quits the whole application, not just this child.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        channel.send(.quit)
        return .terminateCancel
    }

    /// Sends Dock reopen requests through the resident so an exiting child cannot consume them.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        channel.send(.present(.show))
        return false
    }
}
