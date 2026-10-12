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
    static func run() -> Never {
        let channel = PanelChannel(input: .standardInput, output: .standardOutput)
        ClipboardHistoryStore.remoteMutation = { channel.send($0) }
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

final class PanelAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = LauncherModel()
    let channel: PanelChannel
    private let settings = AppSettings.shared
    private var panel: LauncherPanel?
    private var keyMonitor: Any?
    private var appWatcher: AppFolderWatcher?
    private var timer: Timer?
    private var terminationWatch: DispatchSourceSignal?
    private var cancellables = Set<AnyCancellable>()
    private var sequence = 0
    private var lastActivity = Date()
    private var reportedIdle = false
    private var ending = false

    init(channel: PanelChannel) {
        self.channel = channel
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(target: self, about: #selector(openAbout), settings: #selector(openSettings))
        Log.follow(settings).store(in: &cancellables)
        model.hidePanel = { [weak self] in self?.hide() }
        model.showPanel = { [weak self] in self?.show() }
        model.showHUD = { ThawHUD.show(text: $0) }
        model.openSettings = { [weak self] page in
            self?.hide()
            self?.channel.send(.openSettings(page?.id))
        }
        model.residentRequests = { [channel] in channel.send($0) }
        model.canAskAI = AskAI.availabilityCheck { AIAnswer.isAvailable }
        model.typing.window = 0.03
        model.panelWindowSizes(settings: settings)
            .sink { [weak self] size in self?.panel?.resizeKeepingTop(to: size) }
            .store(in: &cancellables)
        followSearchSettings()
        AppPermissions.shared.onPermissionTransition = { [weak self] permission, granted in
            guard granted, permission === AppPermissions.shared.accessibility else { return }
            self?.model.menuBarSearch.accessWasGranted()
            self?.model.refresh()
        }
        settings.onSaved = { [channel] in
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            channel.send(.settings(LinkMessage.Kind.settingsChanged.rawValue, ""))
        }
        SnippetStore.shared.onSaved = { [channel] in channel.send(.settings(LinkMessage.Kind.storeChanged.rawValue, LinkStore.snippets.rawValue)) }
        QuicklinkStore.shared.onSaved = { [channel] in channel.send(.settings(LinkMessage.Kind.storeChanged.rawValue, LinkStore.quicklinks.rawValue)) }
        PreferenceStore.onSaved = { [channel] in channel.send(.settings(LinkMessage.Kind.storeChanged.rawValue, LinkStore.preferences.rawValue)) }
        appWatcher = AppFolderWatcher { [weak self] in self?.model.reloadApps() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            return self.model.handlePanelKey(event, layout: self.settings.launcherLayout) ? nil : event
        }
        OnboardingWindowController.shared.openLauncher = { [weak self] in self?.show() }
        channel.receive = { [weak self] in self?.receive($0) }
        channel.onClose = { [weak self] in self?.end() }
        channel.start()
        watchTermination()
        model.startCatalogLoading()
        IncomingURLRouter.shared.forwardAppearance = { [channel] in channel.send(.settings(LinkMessage.Kind.forwardURL.rawValue, $0.absoluteString)) }
        IncomingURLRouter.shared.install(followsAppearance: false)
        timer = Timer.scheduledOnMain(withTimeInterval: 0.25, repeats: true) { [weak self] in self?.reportIdleIfDue() }
        channel.send(.ready)
    }

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
    }

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
            settings.reload()
            SnippetStore.shared.reload()
            QuicklinkStore.shared.reload()
            model.reloadCommands()
            model.reloadScripts()
            model.refresh()
        case let .timers(timers):
            model.runningTimers.mirror(timers)
            model.refresh()
        case .clipboardChanged:
            ClipboardHistoryStore.shared.reloadMirror()
        default: break
        }
    }

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
            if !OnboardingWindowController.shared.showIfNeeded() {
                show()
            }
        case let .hud(text): ThawHUD.show(text: text)
        case let .url(url): IncomingURLRouter.shared.route(url)
        default: runCommand(request)
        }
    }

    private func runCommand(_ request: PanelRequest) {
        switch request {
        case let .builtIn(key):
            if let item = LauncherModel.hotkeyItems.first(where: { $0.settingsKey == key }) {
                model.runFromHotkey(item)
            }
        case let .command(id, data):
            PanelWork.perform { [model] in
                await model.waitForCommands()
                guard let command = model.commands.first(where: { $0.id == id }) else { return }
                let arguments = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                model.run(command, arguments: arguments)
            }
        case let .script(id):
            PanelWork.perform { [model] in
                await model.waitForScripts()
                if let script = model.allScripts.first(where: { $0.id == id }) {
                    model.run(script)
                }
            }
        default: break
        }
    }

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
        }
        if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
            NSLog("Panel %d shown key=%d active=%d", getpid(), panel.isKeyWindow ? 1 : 0, NSApp.isActive ? 1 : 0)
        }
        model.focusToken += 1
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
            NSLog("Panel %d hiding key=%d active=%d", getpid(), panel.isKeyWindow ? 1 : 0, NSApp.isActive ? 1 : 0)
        }
        panel.orderOut(nil)
        model.panelDidHide()
        lastActivity = Date()
    }

    private func reportIdleIfDue() {
        guard sequence > 0, !reportedIdle,
              Date().timeIntervalSince(lastActivity) >= 0.75,
              !PanelWork.isBusy, !ModalGuard.isActive,
              model.session == nil, model.setup == nil,
              !OnboardingWindowController.shared.isOpen,
              !NSApp.windows.contains(where: \.isVisible)
        else { return }
        reportedIdle = true
        channel.send(.idle(sequence: sequence))
    }

    func windowDidResignKey(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !ModalGuard.isActive, self.panel?.isKeyWindow == false else { return }
            if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
                NSLog("Panel %d resigned; front=%@", getpid(), NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")
            }
            self.hide()
        }
    }

    private func watchTermination() {
        signal(SIGTERM) { _ in }
        let watch = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        watch.setEventHandler { [weak self] in self?.end() }
        watch.resume()
        terminationWatch = watch
    }

    private func end() {
        guard !ending else { return }
        ending = true
        timer?.invalidate()
        if settings.hasUnsavedChanges {
            settings.save()
        }
        model.session?.forceStop()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        channel.drain { exit(0) }
    }

    @objc private func openSettings() {
        hide(); channel.send(.openSettings(nil))
    }

    @objc private func openAbout() {
        hide(); channel.send(.openSettings(SettingsPage.about.id))
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        channel.send(.quit)
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        channel.send(.present(.show))
        return false
    }
}
