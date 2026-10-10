//
//  main.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import Combine
import CryptoKit
import SwiftUI

final class LauncherPanel: NSPanel {
    /// The floating, borderless, see-through window the launcher and the picker both draw their glass in.
    convenience init(size: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        // See LauncherView.margin: the window's own shadow is square.
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool {
        true
    }
}

extension NSView {
    /// Draws the view into a PNG file, for the modes that check a look without showing it.
    /// Answers whether there was anything to draw.
    @discardableResult
    func writePNG(to file: URL) -> Bool {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Read by the App Intents (see Thaw/FloeIntents.swift), which reach the running model through the delegate.
    let model = LauncherModel()
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var panel: LauncherPanel!
    private let hotkeys = HotkeyRegistry()
    private let settings = AppSettings.shared
    /// Settings is a process of its own; this starts it and keeps the two in step.
    private lazy var settingsLink = LauncherSettingsLink(model: model, hotkeys: hotkeys)
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var showItem: NSMenuItem?
    private var appWatcher: AppFolderWatcher?
    /// Kept for the app's lifetime: dropping the token leaves the monitor running but unreachable,
    /// which `leaks` reports.
    private var keyMonitor: Any?
    private var menuBarCommands: MenuBarCommands?
    private var backgroundScheduler: BackgroundScheduler?

    func applicationDidFinishLaunching(_: Notification) {
        Log.follow(settings).store(in: &cancellables)
        settings.$fetchesExchangeRates.removeDuplicates()
            .sink { ExchangeRateUpdater.shared.set(on: $0) }
            .store(in: &cancellables)
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)

        panel = LauncherPanel(size: model.panelState.windowSize(in: settings.launcherLayout))
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LauncherView(model: model).openingLinksInTheChosenBrowser())

        model.hidePanel = { [weak self] in self?.hide() }
        model.showPanel = { [weak self] in self?.show() }
        model.showHUD = { ThawHUD.show(text: $0) }
        model.openSettings = { [weak self] in self?.settingsLink.show(page: $0.map { SettingsPage.extensionPage($0).id }) }
        model.canAskAI = AskAI.availabilityCheck { AIAnswer.isAvailable }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.model.handlePanelKey(event, layout: self.settings.launcherLayout) ? nil : event
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarGlyph.image()
        let menu = NSMenu()
        showItem = menu.addItem(withTitle: String(localized: "Show Floe", bundle: .floe), action: #selector(show), keyEquivalent: "")
        showItem?.target = self
        menu.addItem(withTitle: String(localized: "About Floe", bundle: .floe), action: #selector(openAbout), keyEquivalent: "").target = self
        // Nil until Info.plist carries a Sparkle public key.
        if let updateItem = UpdatesManager.shared.makeMenuItem() {
            menu.addItem(updateItem)
        }
        menu.addItem(withTitle: String(localized: "Settings…", bundle: .floe), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit", bundle: .floe, comment: "The menu item that quits Floe."), action: #selector(NSApplication.terminate), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        NSApp.mainMenu = MainMenu.make(target: self, about: #selector(openAbout), settings: #selector(openSettings))

        appWatcher = AppFolderWatcher { [weak self] in self?.model.reloadApps() }
        // Without duplicates: a reload of the settings saved by the settings process sends every value again.
        settings.$toggleHotkey.removeDuplicates().combineLatest(settings.$commandHotkeys.removeDuplicates(), model.$allCommands, model.$apps)
            .sink { [weak self] _, _, _, _ in DispatchQueue.main.async { self?.registerHotkeys() } }
            .store(in: &cancellables)
        model.$allScripts
            .sink { [weak self] _ in DispatchQueue.main.async { self?.registerHotkeys() } }
            .store(in: &cancellables)
        model.panelWindowSizes(settings: settings)
            .sink { [weak self] size in self?.panel.resizeKeepingTop(to: size) }
            .store(in: &cancellables)
        model.followClipboardRole().store(in: &cancellables)
        // The switch is in the settings process, which stays in front: the launcher only changes its own policy.
        settings.$showInDock.removeDuplicates().dropFirst()
            .sink { NSApp.setActivationPolicy($0 ? .regular : .accessory) }
            .store(in: &cancellables)
        settings.$includeRaycastExtensions.removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.model.reloadCommands() } }
            .store(in: &cancellables)
        // Shortcuts and Spotlight list the commands by name, so they hear about every rescan.
        model.$allCommands
            .sink { _ in DispatchQueue.main.async { FloeShortcuts.updateAppShortcutParameters() } }
            .store(in: &cancellables)
        let menuBarCommands = MenuBarCommands(model: model)
        let backgroundScheduler = BackgroundScheduler(model: model, menuBarCommands: menuBarCommands)
        self.menuBarCommands = menuBarCommands
        self.backgroundScheduler = backgroundScheduler
        model.$allCommands
            .combineLatest(settings.$disabledExtensions.removeDuplicates(), settings.$disabledCommands.removeDuplicates(), settings.$menuBarCommands.removeDuplicates())
            .sink { [weak self] _, _, _, _ in
                // After the publishers' willSet, so enabledCommands reads the new values.
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.menuBarCommands?.sync(self.model.enabledCommands)
                    self.backgroundScheduler?.sync(self.model.enabledCommands)
                }
            }
            .store(in: &cancellables)
        // Everything the panel needs is wired up: the catalog can fill in behind it now.
        model.startCatalogLoading()
        model.typing.window = 0.03
        model.menuBarSearch.warm()
        // Thaw's permission object keeps checking after a request; the menu bar is read the moment the grant lands.
        AppPermissions.shared.onPermissionTransition = { [weak self] permission, granted in
            guard granted, permission === AppPermissions.shared.accessibility else { return }
            self?.model.menuBarSearch.accessWasGranted()
            // A "menu" search in the main panel was showing the row that asks for access.
            self?.model.refresh()
        }
        Log.app.notice("Launched in \(Log.milliseconds(since: processStart)) ms")

        UpdatesManager.shared.performSetup()
        // Takes floe:// links: Thaw's answer about its appearance, and the browser's return once sign-in is back.
        IncomingURLRouter.shared.install()
        TextExpander.shared.start()
        // Made here so copies are recorded from launch, not from the first time the history is looked at.
        _ = ClipboardHistoryStore.shared
        settingsLink.start()

        // The first launch opens the welcome window; the launcher follows when it is finished.
        OnboardingWindowController.shared.openLauncher = { [weak self] in self?.show() }
        if !OnboardingWindowController.shared.showIfNeeded() {
            show()
        }
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
        for command in model.allCommands {
            guard let keyCombination = settings.commandHotkeys[command.id] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in
                guard let self, settings.isEnabled(command) else { return }
                UsageStore.shared.recordUse(of: RootItem.command(command).id)
                model.run(command)
            }
        }
        for script in model.allScripts {
            guard let keyCombination = settings.commandHotkeys[script.id] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in
                UsageStore.shared.recordUse(of: RootItem.script(script).id)
                self?.model.run(script)
            }
        }
        for (item, keyCombination) in LauncherModel.assigned(settings.commandHotkeys) {
            _ = hotkeys.register(keyCombination) { [weak self] in self?.model.runFromHotkey(item) }
        }
        for app in model.apps {
            guard let key = RootItem.app(app).settingsKey, let keyCombination = settings.commandHotkeys[key] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in self?.model.toggleApp(app) }
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

    func applicationWillTerminate(_: Notification) {
        model.session?.forceStop()
        menuBarCommands?.stopAll()
        backgroundScheduler?.stopAll()
        settingsLink.terminate()
        ClipboardHistoryStore.flushShared()
        UsageStore.shared.flush()
    }

    private func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    @objc private func show() {
        guard !panel.isVisible || !panel.isKeyWindow else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(model.panelState.origin(in: frame, panelSize: panel.frame.size))
        }
        model.panelWillShow()
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.panelDidHide()
    }

    func windowDidResignKey(_: Notification) {
        // Checked a turn later, once focus has settled; an open file panel keeps the launcher up.
        DispatchQueue.main.async { [self] in
            if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
                let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                FileHandle.standardError.write(Data("resignKey: key=\(String(describing: NSApp.keyWindow)) frontmost=\(front)\n".utf8))
            }
            if !ModalGuard.isActive, !panel.isKeyWindow {
                hide()
            }
        }
    }
}

/// `Floe --selftest <extension> <command>` runs a command without UI and reports the first list it renders.
func runSelfTest(extensionName: String, commandName: String) -> Never {
    guard let command = ExtensionCommand.scan().first(where: { $0.extensionName == extensionName && $0.name == commandName }) else {
        print("SELFTEST FAIL: no command \(extensionName)/\(commandName)")
        exit(1)
    }
    let missing = PreferenceStore.missingRequired(for: command).map(\.name)
    if !missing.isEmpty {
        print("SELFTEST missing required preferences: \(missing)")
    }
    let session = ExtensionSession(command: command)
    session.onMessage = { print("SELFTEST message:", $0["type"] ?? "?") }
    let observer = session.objectWillChange.sink { _ in
        DispatchQueue.main.async {
            if let failure = session.failure {
                print("SELFTEST FAILURE: kind=\(failure.kind) message=\(failure.message.debugDescription) logLines=\(failure.details.split(separator: "\n").count)")
                session.forceStop()
                exit(0)
            }
            if let toast = session.toast, toast.style == "failure" {
                print("SELFTEST TOAST: \(toast.title): \(toast.message ?? "")")
            }
            let rows = session.rows
            let markdown = session.view?.type == "Detail" ? session.view?.string("markdown") : nil
            guard rows.first != nil || markdown != nil else { return }
            let actions = session.actions.compactMap { $0.string("title") }.joined(separator: " | ")
            let summary = markdown.map { "markdown=\($0.prefix(60).debugDescription)" }
                ?? "rows=\(rows.count) first=\"\(rows[0].node.string("title") ?? "")\""
            print("SELFTEST OK: view=\(session.view?.type ?? "?") \(summary) actions=[\(actions)]")
            let describe = { (entries: [MenuEntry]) in
                entries.map { "\($0.section.map { "[\($0)] " } ?? "")\($0.node.string("title") ?? "?")\($0.isSubmenu ? " ›" : "")" }.joined(separator: ", ")
            }
            print("SELFTEST MENU: \(describe(session.menuEntries))")
            if let submenu = session.menuEntries.first(where: \.isSubmenu) {
                session.openSubmenu(submenu.node)
                print("SELFTEST SUBMENU: \(describe(session.menuEntries))")
                session.closeSubmenuOrMenu()
            }
            session.actionQuery = "copy"
            print("SELFTEST MENU SEARCH copy: \(describe(session.menuEntries))")
            session.forceStop()
            exit(0)
        }
    }
    session.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        print("SELFTEST FAIL: timed out; view=\(session.view?.type ?? "none") toast=\(session.toast?.title ?? "none")")
        session.forceStop()
        exit(1)
    }
    withExtendedLifetime(observer) { RunLoop.main.run() }
    exit(1)
}

Paths.prepareSupportFolders()
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
    // No sources: the process exits before they answer, and a tab read must not start from here.
    let model = LauncherModel(snapshot: .scanningNow(includeRaycast: AppSettings.shared.includeRaycastExtensions), sources: [])
    model.canAskAI = { AIAnswer.isAvailable }
    model.query = query
    for result in model.results.prefix(8) {
        print("\(result.section.map { "[\($0)] " } ?? "")\(result.item.title) (\(result.item.kind))\(model.alias(for: result.item).map { " (alias \($0))" } ?? "")")
    }
    exit(0)
}

if options.benchSearch {
    runSearchBench(queries: options.rest)
}

// Catches slow page switches.
if options.benchSettings {
    _ = NSApplication.shared
    let catalog = SettingsCatalog(snapshot: .scanningNow(includeRaycast: AppSettings.shared.includeRaycastExtensions))
    let selection = SettingsSelection()
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 820, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
    let search = SearchModel()
    window.contentView = NSHostingView(rootView: SettingsView(catalog: catalog, settings: .shared, selection: selection, search: search))
    window.orderFrontRegardless()
    let pages: [(String, SettingsPage)] = [("general", .general), ("applications", .applications), ("privacy", .privacy), ("about", .about), ("extension", .extensionPage("kill-process"))]
    for (name, page) in pages {
        let start = Date()
        selection.page = page
        // Let SwiftUI process the change, then force layout and drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        print("BENCH \(name): \(Int(Date().timeIntervalSince(start) * 1000 - 50)) ms")
        if let directory = ProcessInfo.processInfo.environment["FLOE_BENCH_DUMP"] {
            window.contentView?.writePNG(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
    runSettingsSearchBench(search: search, window: window)
    // General's AI section sits below the fold, so each of its states is drawn on its own, on scratch settings.
    if let directory = ProcessInfo.processInfo.environment["FLOE_BENCH_DUMP"], let scratch = UserDefaults(suiteName: "floe.bench.\(UUID().uuidString)") {
        // Name, source, the API's model and key, the tool chosen by name, and the API's service.
        let states: [(String, AISource, String, String?, AITool?, AIService)] = [
            ("ai-tools", .tools, "", nil, nil, .openAI), ("ai-tool-model", .tools, "", nil, .opencode, .openAI),
            ("ai-api", .api, "small", "key-123", nil, .openAI), ("ai-api-incomplete", .api, "", nil, nil, .openAI), ("ai-api-zai", .api, "", nil, nil, .zai),
        ]
        for (name, source, aiModel, key, tool, service) in states {
            let settings = AppSettings(defaults: scratch)
            settings.aiSource = source
            settings.aiModel = aiModel
            settings.aiTool = tool
            settings.aiBaseURL = service.baseURL ?? ""
            let section = Form { AISettingsSection(settings: settings, storedKey: key ?? "") }.formStyle(.grouped).frame(width: 600, height: 320)
            window.contentView = NSHostingView(rootView: section)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            window.contentView?.writePNG(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
    exit(0)
}

// Mixed-up or invisible icons show up without opening the window.
if options.iconCheck {
    _ = NSApplication.shared
    let samples: [(String, Any, String)] = ExtensionCommand.scan().uniqued(on: \.extensionName).map { command in
        (command.extensionName, command.icon ?? "", command.assetsPath)
    } + [("kill-process accessory", ["source": "cpu.svg", "tintColor": "color:PrimaryText"], ExtensionCommand.scan().first { $0.extensionName == "kill-process" }?.assetsPath ?? "")]
    for (name, value, assets) in samples {
        let renderer = ImageRenderer(content: IconView(value: value, assetsPath: assets, size: 32, waitsForImage: true).environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let image = renderer.cgImage, let data = image.dataProvider?.data as Data? else { print("\(name): no image"); continue }
        // A pixel counts as drawn when any of its four bytes is set, whatever the channel order.
        let pixels = stride(from: 0, to: data.count - 3, by: 4).filter { data[$0] | data[$0 + 1] | data[$0 + 2] | data[$0 + 3] > 8 }.count
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(8)
        if let directory = ProcessInfo.processInfo.environment["FLOE_ICON_DUMP"] {
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            try? png?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        print("\(name.padding(toLength: 24, withPad: " ", startingAt: 0)) sha=\(digest) drawn=\(pixels * 100 / max(1, data.count / 4))%")
    }
    exit(0)
}

if options.menuBar {
    let query = options.rest.first ?? ""
    let extras = MenuBarExtras.scan()
    print("MENUBAR trusted=\(MenuBarExtras.isTrusted) items=\(extras.count)")
    let ranked = query.isEmpty ? extras : extras.filter { Fuzzy.score(query, $0.name) != nil || Fuzzy.score(query, $0.ownerName) != nil }
    for extra in ranked.prefix(30) {
        print("  \(extra.name) (\(extra.ownerName)) at \(Int(extra.frame.minX)),\(Int(extra.frame.minY))")
    }
    exit(0)
}

if let path = options.panelSnapshot {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: path)
    let model = LauncherModel(snapshot: .scanningNow(includeRaycast: AppSettings.shared.includeRaycastExtensions))
    // Scratch settings, so drawing the compact layout leaves the saved one alone.
    let settings = AppSettings(defaults: UserDefaults(suiteName: "floe.snapshot") ?? .standard)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: model.panelState.windowSize(in: settings.launcherLayout)), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: LauncherView(model: model, settings: settings))
    window.orderFrontRegardless()
    let resizing = model.panelWindowSizes(settings: settings).sink { window.resizeKeepingTop(to: $0) }
    func snapshot(_ name: String, wait: TimeInterval = 1) {
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        guard window.contentView?.writePNG(to: folder.appendingPathComponent("\(name).png")) == true else { return }
        print("SNAPSHOT \(name) \(Int(window.frame.width))x\(Int(window.frame.height)) top=\(Int(window.frame.maxY))")
    }
    model.query = "co"
    snapshot("root")
    settings.launcherLayout = .compact
    snapshot("compact-query")
    model.query = ""
    snapshot("compact")
    settings.launcherLayout = .extended
    for shape in [SearchFieldShape.capsule, .square] {
        settings.searchFieldShape = shape
        snapshot("field-\(shape.rawValue)")
    }
    settings.searchFieldShape = .rounded
    // The answer view with a canned answer: nothing is asked of any source.
    model.askAIRequest = { conversation, _ in conversation.earlier.isEmpty ? AskAI.sampleAnswer : AskAI.sampleFollowUp }
    MarkdownView.isSelectable = false
    model.openAskAI("how do tides work")
    snapshot("ask-ai")
    model.closeAskAI()
    model.openMenuBarSearch()
    snapshot("menubar", wait: 5)
    // The field as its own piece, last so the pictures above are drawn as they always were.
    settings.separatesSearchField = true
    snapshot("separate-menubar")
    model.closeMenuBarSearch()
    model.query = "co"
    for shape in SearchFieldShape.allCases {
        settings.searchFieldShape = shape
        snapshot("separate-\(shape.rawValue)")
    }
    settings.searchFieldShape = .rounded
    settings.launcherLayout = .compact
    model.query = ""
    snapshot("separate-compact")
    settings.launcherLayout = .extended
    settings.separatesSearchField = false
    // A follow-up under its first answer, both canned, and last for the same reason. The look
    // settles first: a change of it draws the whole panel anew, which the answer view takes as leaving.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    model.openAskAI("how do tides work")
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    model.askAI?.draft = "and why two a day"
    model.askAI?.askFollowUp()
    snapshot("ask-ai-follow-up")
    // Three presses of the up arrow: the end of the first answer over the follow-up.
    for _ in 0 ..< 3 {
        model.askAI?.scroll(by: -1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
    snapshot("ask-ai-earlier")
    model.closeAskAI()
    // Saved now: the edit is otherwise written a moment later, after this has exited.
    settings.save()
    resizing.cancel()
    exit(0)
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
