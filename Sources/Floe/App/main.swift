//
//  main.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// Floe itself: the launcher and everything it keeps running, in one process that stays. Only Settings is a process
/// of its own, started when it opens and gone when it closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The clipboard history, recorded from launch.
    private let clipboard = ClipboardHistoryStore()
    private(set) lazy var model = LauncherModel(clipboard: clipboard)
    private let hotkeys = HotkeyRegistry()
    private let settings = AppSettings.shared
    /// Settings is a process of its own; this starts it and keeps the two in step.
    private lazy var settingsLink = LauncherSettingsLink(model: model, clipboard: clipboard, hotkeys: hotkeys)
    private lazy var launcher = LauncherWindow(model: model, settings: settings) { [weak self] in self?.settingsLink.show(page: $0?.id) }
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var showItem: NSMenuItem?
    private var appWatcher: AppFolderWatcher?
    private var menuBarCommands: MenuBarCommands?
    private var backgroundScheduler: BackgroundScheduler?

    /// Starts the services, the launcher's window and the routes into it. The window itself is made on its first show.
    func applicationDidFinishLaunching(_: Notification) {
        // Only this process moves the storage off the old key; Settings and the self-test never do.
        StorageMigration.shared.begin()
        Log.follow(settings).store(in: &cancellables)
        settings.$fetchesExchangeRates.removeDuplicates()
            .filter { !$0 }
            .sink { _ in ExchangeRateStore.remove() }
            .store(in: &cancellables)
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        // Copies left by a launch that crashed are plain images, and no extension of this launch has asked for them.
        PasteboardContent.removeReadableCopies()

        launcher.start()
        // Settings' changes reach the search at once: they are this process's own settings, read again.
        settingsLink.onChange = { [weak self] in self?.model.refresh() }

        (statusItem, showItem) = StatusMenu.make(target: self, show: #selector(show), about: #selector(openAbout), settings: #selector(openSettings))
        NSApp.mainMenu = MainMenu.make(target: self, about: #selector(openAbout), settings: #selector(openSettings), includesWindowMenu: false)
        // Hidden, Floe is still reached by its hotkey, the Dock if it is there, or by opening the app again.
        settings.$showInMenuBar.removeDuplicates()
            .sink { [weak self] in self?.statusItem?.isVisible = $0 }
            .store(in: &cancellables)

        appWatcher = AppFolderWatcher { [weak self] in self?.model.catalog.reloadApps() }
        // Without duplicates: a reload of the settings saved by the settings process sends every value again.
        settings.$toggleHotkey.removeDuplicates().combineLatest(settings.$commandHotkeys.removeDuplicates(), model.catalog.$allCommands, model.catalog.$apps)
            .sink { [weak self] _, _, _, _ in DispatchQueue.main.async { self?.registerHotkeys() } }
            .store(in: &cancellables)
        model.catalog.$allScripts
            .sink { [weak self] _ in DispatchQueue.main.async { self?.registerHotkeys() } }
            .store(in: &cancellables)
        // The switch is in the settings process, which stays in front: the launcher only changes its own policy.
        settings.$showInDock.removeDuplicates().dropFirst()
            .sink { NSApp.setActivationPolicy($0 ? .regular : .accessory) }
            .store(in: &cancellables)
        model.catalog.followRaycastSwitch().store(in: &cancellables)
        // Shortcuts and Spotlight list the commands by name, so they hear about every rescan.
        model.catalog.$allCommands
            .sink { _ in DispatchQueue.main.async { FloeShortcuts.updateAppShortcutParameters() } }
            .store(in: &cancellables)
        let menuBarCommands = MenuBarCommands(model: model)
        let backgroundScheduler = BackgroundScheduler(model: model, menuBarCommands: menuBarCommands)
        self.menuBarCommands = menuBarCommands
        self.backgroundScheduler = backgroundScheduler
        model.catalog.$allCommands
            .combineLatest(settings.$disabledExtensions.removeDuplicates(), settings.$disabledCommands.combineLatest(settings.$enabledCommands).removeDuplicates(by: ==), settings.$menuBarCommands.removeDuplicates())
            .sink { [weak self] _, _, _, _ in
                // After the publishers' willSet, so enabledCommands reads the new values.
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.menuBarCommands?.sync(self.model.enabledCommands)
                    self.backgroundScheduler?.sync(self.model.enabledCommands)
                }
            }
            .store(in: &cancellables)
        model.startCatalogLoading()
        Log.app.notice("Launched in \(Log.milliseconds(since: processStart)) ms")

        UpdatesManager.shared.performSetup()
        // Takes floe:// links: Thaw's answer about its appearance, and the browser's return once sign-in is back.
        IncomingURLRouter.shared.install()
        TextExpander.shared.follow(SnippetStore.shared)
        settingsLink.start()

        if ProcessInfo.processInfo.environment["FLOE_RESIDENT_BENCH"] == nil {
            launcher.perform(.onboarding)
        }
        ResidentBench.start(launcher: launcher)
        model.autorun()
        // FLOE_OPEN_SETTINGS=<seconds>[,<seconds>] opens Settings that long after launch, to check the settings process.
        for delay in (ProcessInfo.processInfo.environment["FLOE_OPEN_SETTINGS"] ?? "").split(separator: ",").compactMap({ Double($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.settingsLink.show() }
        }
    }

    /// The launcher hotkey plus one per command that has a hotkey assigned.
    private func registerHotkeys() {
        hotkeys.unregisterAll()
        if let toggleHotkey = settings.toggleHotkey {
            _ = hotkeys.register(toggleHotkey) { [weak self] in self?.toggle() }
        }
        showItem?.title = settings.toggleHotkey.map { String(localized: "Show Floe (\($0.displayValue))", bundle: .floe, comment: "A menu item. The placeholder is a keyboard shortcut such as ⌥Space.") } ?? String(localized: "Show Floe", bundle: .floe)
        for command in model.catalog.allCommands {
            guard let keyCombination = settings.commandHotkeys[command.id] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in
                guard let self, settings.isEnabled(command) else { return }
                UsageStore.shared.recordUse(of: RootItem.command(command).id)
                model.runner.run(command)
            }
        }
        for script in model.catalog.searchedScripts {
            guard let keyCombination = settings.commandHotkeys[script.id] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in
                self?.launcher.perform(.script(script.id))
            }
        }
        for (item, keyCombination) in LauncherModel.assigned(settings.commandHotkeys) {
            _ = hotkeys.register(keyCombination) { [weak self] in self?.model.runFromHotkey(item) }
        }
        for app in model.catalog.apps {
            guard let key = RootItem.app(app).settingsKey, let keyCombination = settings.commandHotkeys[key] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in self?.model.runAppHotkey(app) }
        }
    }

    @objc func openAbout() {
        hide()
        settingsLink.show(page: SettingsPage.about.id)
    }

    @objc func openSettings() {
        hide()
        settingsLink.show()
    }

    /// A click on the Dock icon opens the launcher.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        show()
        return false
    }

    /// Quits once the notes views have saved what they hold.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        launcher.finish { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        shutDown()
    }

    /// Flushes what is kept and stops the processes Floe started, before quitting or ending a benchmark.
    func shutDown() {
        model.runner.stopAll()
        menuBarCommands?.stopAll()
        backgroundScheduler?.stopAll()
        settingsLink.terminate()
        // The extensions that read the plain copies of clipboard images have stopped.
        PasteboardContent.removeReadableCopies()
        clipboard.flush()
        UsageStore.shared.flush()
        FileIndexService.shared.flush()
    }

    private func toggle() {
        launcher.toggle()
    }

    @objc private func show() {
        launcher.show()
    }

    private func hide() {
        launcher.hide()
    }
}

Paths.prepareSupportFolders()
StorageKey.isEnabled = true
EarlierIdentifier.importSettings()
AutoFillOptOut.install()

let processStart = Date()
let options = DebugOptions.parseOrExit()

if options.pick {
    PickerMode.run(options)
}

if options.settings {
    SettingsMode.run(options)
}

if let query = options.search {
    runSearch(query: query)
}

if options.benchSearch {
    runSearchBench(queries: options.rest)
}

if options.benchSettings {
    runSettingsPageBench()
}

if options.iconCheck {
    runIconCheck()
}

if options.menuBar {
    runMenuBarListing(query: options.rest.first ?? "")
}

if let path = options.panelSnapshot {
    runPanelSnapshot(path: path)
}

if options.selftest.count == 2 {
    runSelfTest(extensionName: options.selftest[0], commandName: options.selftest[1])
}

// Read once, in the background: extensions and AI.ask run tools found on the login shell's PATH.
Task { await LoginEnvironment.load() }
// From here on a frozen main thread leaves a report in ~/Library/Logs/Floe.
HangWatchdog.start()

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
