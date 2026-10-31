//
//  LauncherWindow.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine
import SwiftUI
import ThawUI

/// What the launcher can be asked to show or do from outside its window: the hotkeys, the menu bar icon, App Intents
/// and links.
nonisolated enum PanelRequest: Codable, Equatable, Sendable {
    case show, toggle, hide, onboarding
    case command(String, arguments: Data?, context: Data? = nil)
    case script(String)
    case builtIn(String)
    case hud(String)
    case url(URL)
}

/// The launcher's window, with onboarding and the floating note beside it, kept for as long as Floe runs so the hotkey
/// shows a window already made. Closed a while, or under memory pressure, it lets go of what it can draw again.
final class LauncherWindow: NSObject, NSWindowDelegate {
    private let model: LauncherModel
    private let settings: AppSettings
    private let openSettings: (SettingsPage?) -> Void
    private lazy var onboarding = OnboardingWindowController(settings: settings, permissions: .shared)
    private lazy var floatingNote = FloatingNoteWindowController(settings: settings) { [weak self] in self?.model.record($0) }
    private var panel: LauncherPanel?
    private var keyMonitor: Any?
    private var pressureWatch: DispatchSourceMemoryPressure?
    /// Memory ran short while the launcher was on screen: it lets go of what it can once it closes.
    private var trimsWhenHidden = false
    /// How long the launcher stays closed before it lets go of what it can draw again.
    private let idleTrimDelay: Duration
    private var idleTrim: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(model: LauncherModel, settings: AppSettings, idleTrimDelay: Duration = .seconds(300), openSettings: @escaping (SettingsPage?) -> Void) {
        self.model = model
        self.settings = settings
        self.idleTrimDelay = idleTrimDelay
        self.openSettings = openSettings
    }

    func start() {
        model.panelHost = PanelHost(
            hidePanel: { [weak self] in self?.hide() },
            showPanel: { [weak self] in self?.show() },
            showHUD: { ThawHUD.show(text: $0) },
            openSettings: { [weak self] page in
                self?.hide()
                self?.openSettings(page)
            }
        )
        model.panelHost.showFloatingNote = { [weak self] in self?.floatingNote.show() }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            return self.model.handlePanelKey(event, layout: self.settings.launcherLayout) ? nil : event
        }
        onboarding.openLauncher = { [weak self] in self?.show() }
        Confirm.inPanel = { [weak self] in self?.model.ask($0) }
        IntentHandler.current = .serving(model) { [weak self] in self?.perform($0) }
        OAuthBroker.shared.say { ThawHUD.show(text: $0) }
        watchMemoryPressure()
    }

    /// Spotlight's recency and the exchange rates are the search's, and follow their switches.
    private func followSearchSettings() {
        model.followClipboardRole().store(in: &cancellables)
        settings.$indexesFileNames.removeDuplicates()
            .sink { RecentFileUse.shared.follow($0) }
            .store(in: &cancellables)
        settings.$fetchesExchangeRates.removeDuplicates()
            .sink { ExchangeRateUpdater.shared.set(on: $0) }
            .store(in: &cancellables)
    }

    func perform(_ request: PanelRequest) {
        switch request {
        case .show: show()
        case .toggle: toggle()
        case .hide: hide()
        case .onboarding:
            Task {
                // Until macOS answers, granted notifications read as unanswered and would bring the access step back.
                await TimerAlerts.readStatus()
                if !onboarding.showIfNeeded() {
                    show()
                }
            }
        case let .hud(text): ThawHUD.show(text: text)
        case let .url(url): IncomingURLRouter.shared.route(url)
        case .builtIn, .command, .script: run(request)
        }
    }

    /// A built-in, a command or a script, once the catalog that has it is loaded.
    private func run(_ request: PanelRequest) {
        switch request {
        case let .builtIn(key):
            if let item = LauncherModel.hotkeyItems.first(where: { $0.settingsKey == key }) {
                model.runFromHotkey(item)
            }
        case let .command(id, data, context):
            Task { [model] in
                await model.catalog.waitForCommands()
                guard let command = model.commands.first(where: { $0.id == id }) else { return }
                model.runner.run(command, arguments: CommandLauncher.object(data), context: CommandLauncher.object(context))
            }
        case let .script(id):
            Task { [model] in
                await model.catalog.waitForScripts()
                if let script = model.catalog.allScripts.first(where: { $0.id == id }) {
                    model.features.scripts.run(script)
                }
            }
        default: break
        }
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Made on the first show, and again after memory pressure let it go; the benchmark draws it offscreen.
    func show() {
        idleTrim?.cancel()
        idleTrim = nil
        if panel == nil {
            let created = LauncherPanel(size: model.panelState.windowSize(in: settings.launcherLayout))
            created.delegate = self
            created.contentView = NSHostingView(rootView: LauncherView(model: model).openingLinksInTheChosenBrowser())
            panel = created
        }
        guard let panel, !panel.isVisible || !panel.isKeyWindow else { return }
        let screen = LauncherScreen.screen(chosen: settings.launcherScreen)
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(model.panelState.origin(in: frame, panelSize: panel.frame.size))
        }
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
        model.focusToken += 1
        model.panelDidShow()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        model.panelDidHide()
        if trimsWhenHidden {
            trim()
        }
        scheduleIdleTrim()
    }

    /// Trims once the launcher has stayed closed for the delay. A show before then calls it off.
    func scheduleIdleTrim() {
        idleTrim?.cancel()
        idleTrim = Task { [weak self, delay = idleTrimDelay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.trim()
        }
    }

    /// Defers dismissal so AppKit can finish transferring focus to any modal surface.
    func windowDidResignKey(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !ModalGuard.isActive, self.panel?.isKeyWindow == false else { return }
            self.hide()
        }
    }

    // MARK: Memory

    /// Each warning from macOS trims once, now or when the launcher next closes, without the idle wait.
    /// Nothing stays switched: once memory is back, the launcher keeps what it makes as before.
    private func watchMemoryPressure() {
        let watch = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        watch.setEventHandler { [weak self, weak watch] in
            guard let self, let event = watch?.data else { return }
            guard event.contains(.warning) || event.contains(.critical) else {
                trimsWhenHidden = false
                return
            }
            if isVisible {
                trimsWhenHidden = true
            } else {
                trim()
            }
        }
        watch.resume()
        pressureWatch = watch
    }

    /// Lets go of the window's drawing, the icons and the results, all of which the next show makes again.
    func trim() {
        trimsWhenHidden = false
        guard !isVisible, !ModalGuard.isActive, model.runner.session == nil, model.setup == nil else { return }
        panel?.contentView = nil
        panel = nil
        model.reset()
        IconThumbnailCache.shared.removeAll()
        URLCache.shared.removeAllCachedResponses()
        // The allocator keeps freed pages for later; this hands them back to macOS.
        malloc_zone_pressure_relief(nil, 0)
    }

    // MARK: Quitting

    /// Saves what the notes views hold, then calls back: Floe waits for it before it quits.
    func finish(then done: @escaping () -> Void) {
        if settings.hasUnsavedChanges {
            settings.save()
        }
        let deskSave = model.noteDeskSave
        // A notes app that never answers must not keep Floe from quitting: the desk's save gets five seconds,
        // then the floating note saves with five of its own.
        waitAtMost(.seconds(5), for: { _ = await deskSave?.value }, then: { [floatingNote] in floatingNote.finish(then: done) })
    }
}
