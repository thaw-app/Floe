//
//  Model.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices
import Combine

final class LauncherModel: ObservableObject {
    @Published var query = "" {
        didSet { typing.changed { [weak self] in self?.refresh() } }
    }

    let typing = TypingSettle()
    /// The text the results on screen answer. While typing is paced it trails `query`, and rows mark their matches by it.
    private(set) var searchedQuery = ""

    @Published private(set) var results: [RootResult] = [] {
        didSet {
            resultsVersion += 1
            rowSelection.reset()
            tellTheSelectedRow()
        }
    }

    @Published var selection = 0 {
        didSet { tellTheSelectedRow() }
    }

    /// Counts every new list of results, so the list view knows one from the next without comparing rows.
    private(set) var resultsVersion = 0
    let rowSelection = RowSelection()

    private func tellTheSelectedRow() {
        rowSelection.select(results.indices.contains(selection) ? results[selection].id : nil)
    }

    @Published private(set) var session: ExtensionSession?
    /// The setup form on screen, if any. What is typed into it is `setupForm`'s.
    @Published var setup: SetupRequest?
    /// Not published: typing in the form redraws the form only.
    let setupForm = SetupFormModel()
    /// Bumped whenever the panel is shown so the search field can take focus again.
    @Published var focusToken = 0
    /// Every command found, including those of disabled extensions; the settings window lists these.
    @Published private(set) var allCommands: [ExtensionCommand] = []
    /// Every script command found in the Scripts folder.
    @Published private(set) var allScripts: [ScriptCommand] = []
    /// System Settings' panes, found once at launch: they only change with the system.
    private var settingsPanes: [SystemSettingsPane] = []
    /// The hosts of the SSH configuration, read again each time the panel opens.
    private var sshHosts: [SSHHost] = []
    /// How a host's connection is opened. Tests replace it, so they open nothing.
    var sshConnector = SSHConnector.system
    /// The shortcuts of Apple's Shortcuts app and their runs. Nothing is read while the switch in Privacy is off.
    let shortcutLibrary = AppleShortcutLibrary()
    /// Files in the Scripts folder that failed to parse, for the settings pane.
    @Published private(set) var scriptFailures: [ScriptFailure] = []
    /// True until the first apps and commands scans have both published, or a snapshot was injected.
    @Published private(set) var isLoadingCatalog = true

    /// True while the panel shows the file search instead of the root search.
    @Published var isSearchingFiles = false
    /// The file search's own state. Not published: its changes redraw its view only.
    let fileSearch = FileSearchModel()

    /// True while the panel shows the menu bar item search instead of the root search.
    @Published var isSearchingMenuBar = false
    /// True while the panel shows the clipboard history instead of the root search.
    @Published var isShowingClipboardHistory = false
    /// The clipboard history view's own state. Not published: its changes redraw its view only.
    let clipboardHistory: ClipboardHistoryModel
    /// The question on screen and its answer, while the panel shows them instead of the root search.
    @Published var askAI: AskAIModel?
    /// Answers the question. A test replaces it: the real thing reaches the chosen AI source.
    var askAIRequest: AskAIModel.Request = AskAIModel.live
    /// Whether an AI source can answer. The app delegate sets it; without one no Ask AI row is offered.
    var canAskAI: () -> Bool = { false }
    /// The menu bar item search's own state. Not published: its changes redraw its view only.
    let menuBarSearch: MenuBarSearchModel

    // The app delegate replaces these; the defaults keep the model usable without a window.
    var hidePanel: () -> Void = { /* no panel */ }
    var showPanel: () -> Void = { /* no panel */ }
    var showHUD: (String) -> Void = { _ in
        // No HUD.
    }

    /// Opens the settings window, optionally on one extension's page.
    var openSettings: (String?) -> Void = { _ in
        // No settings window.
    }

    /// Pops the Actions menu of the search that is on screen: root, files or menu bar items.
    var showActions: () -> Void = { /* set by the Actions button */ }

    /// The scope whose rows are on screen, when the query names one.
    private(set) var activeScope: ScopeMatch?
    /// True while a scope's rows are still on their way.
    @Published private(set) var isAwaitingResults = false
    /// Stands in for opening a scope's row. Tests set it: the real thing pastes and clicks outside the launcher.
    var scopeResultOpener: ((RootItem) -> Void)?
    private let scopes: [any SearchScope]
    private let scopeUpdates = SearchUpdates()
    /// The optional sources, and the rows they found for the ordinary search on screen.
    private let sources: [any SearchSource]
    private let sourceSearch = SourceSearch()

    let settings: AppSettings
    /// How the terminal and the editor are looked up. Tests replace it, so they do not read this Mac's apps;
    /// replacing it also drops what the roles resolved to, the way a changed choice does.
    var appLookup = AppLookup.system {
        didSet { invalidateResolvedApps() }
    }

    /// What `preferredApps` and `resolvedClipboardDestination` resolved last. Both reach LaunchServices,
    /// which no keystroke should: the search reads them resolved once, until `invalidateResolvedApps()`.
    private var cachedPreferredApps: [RoleApp]?
    private var cachedClipboardDestination: ClipboardDestination?
    private var cancellables: Set<AnyCancellable> = []
    var clipboardOpener = ClipboardOpener.system
    var linkOpener = LinkOpener.system
    var preferredApps: [RoleApp] {
        if let cached = cachedPreferredApps {
            return cached
        }
        let resolved = PreferredApps.apps(choice: settings.appChoice, installed: appLookup)
        cachedPreferredApps = resolved
        return resolved
    }

    /// Where the Clipboard History command goes, resolved the same once-per-change way as `preferredApps`.
    var resolvedClipboardDestination: ClipboardDestination {
        if let cached = cachedClipboardDestination {
            return cached
        }
        let resolved = settings.clipboardDestination(installed: appLookup)
        cachedClipboardDestination = resolved
        return resolved
    }

    /// Drops what the roles resolved to: a choice changed, an app folder did, or a test put its own lookup in.
    func invalidateResolvedApps() {
        cachedPreferredApps = nil
        cachedClipboardDestination = nil
    }

    let usage: UsageStore
    /// What the shell rows reach outside the launcher through. Tests replace its parts.
    var shell = ShellEnvironment()
    /// Where receipts are kept. Tests give one of their own.
    var receipts = ReceiptStore.shared
    var checkpointStore = CheckpointStore.shared
    var checkpointing = CheckpointEnvironment()
    var reminding = ReminderEnvironment()
    var scheduling = EventEnvironment()
    var timing = TimerEnvironment()
    var music = MusicEnvironment()
    let runningTimers = RunningTimers()
    /// The saved checkpoints, read when the launcher opens and when one is saved or deleted.
    var checkpoints: [Checkpoint] = []
    /// Where in the remembered searches the field stands, while the Up arrow walks back through them.
    var recalledQuery: Int?
    private let scanner: any CatalogScanning
    /// Bumped per request, so a result can tell whether its request is still the newest one.
    private var appsGeneration = 0
    private var commandsGeneration = 0
    private var scriptsGeneration = 0
    private var appsTask: Task<Void, Never>?
    private var commandsTask: Task<Void, Never>?
    private var scriptsTask: Task<Void, Never>?
    private var hasLoadedApps = false
    private var hasLoadedCommands = false
    private var hasLoadedScripts = false
    private var didAutorun = false
    private var pendingReset: DispatchWorkItem?
    /// Watches the open command's extension while it is one being developed (see HotReload.swift).
    private var sourceWatcher: DirectoryWatcher?
    @Published private(set) var apps: [AppEntry] = []
    private var commands: [ExtensionCommand] {
        CommandLookup.enabled(allCommands, disabledExtensions: settings.disabledExtensions, disabledCommands: settings.disabledCommands)
    }

    /// Every command that may run on its own: a menu-bar command only once it was put in the menu bar.
    /// Controllers read this and filter by mode.
    var enabledCommands: [ExtensionCommand] {
        commands.filter { $0.mode != "menu-bar" || settings.menuBarCommands.contains($0.id) }
    }

    func isInMenuBar(_ command: ExtensionCommand) -> Bool {
        settings.menuBarCommands.contains(command.id)
    }

    /// Gives a menu-bar command its status item, or takes it away again.
    func toggleMenuBarCommand(_ command: ExtensionCommand) {
        if settings.menuBarCommands.remove(command.id) != nil {
            showHUD(String(localized: "Removed from Menu Bar", bundle: .floe))
        } else {
            settings.menuBarCommands.insert(command.id)
            showHUD(String(localized: "Added to Menu Bar", bundle: .floe))
        }
        refresh()
    }

    /// True when a command can run unattended: no missing required preferences or arguments.
    func canRunUnattended(_ command: ExtensionCommand) -> Bool {
        PreferenceStore.missingRequired(for: command).isEmpty
            && command.arguments.allSatisfy { !$0.required }
    }

    /// Construction never scans: without a snapshot the model starts with the built-in entries only,
    /// and `startCatalogLoading()` fills in the rest once the UI is wired up.
    init(
        scanner: any CatalogScanning = CatalogLoader(),
        settings: AppSettings = .shared,
        usage: UsageStore = .shared,
        snapshot: CatalogSnapshot? = nil,
        scopes: [any SearchScope] = RootSearch.standardScopes(),
        sources: [any SearchSource] = RootSearch.standardSources()
    ) {
        self.scopes = scopes
        self.sources = sources
        self.scanner = scanner
        self.settings = settings
        self.usage = usage
        menuBarSearch = MenuBarSearchModel(settings: settings)
        clipboardHistory = ClipboardHistoryModel(usage: usage)
        if let snapshot {
            apps = snapshot.apps
            allCommands = snapshot.commands
            allScripts = snapshot.scripts
            scriptFailures = snapshot.scriptFailures
            settingsPanes = snapshot.settingsPanes
            sshHosts = snapshot.sshHosts
            hasLoadedApps = true
            hasLoadedCommands = true
            hasLoadedScripts = true
            isLoadingCatalog = false
        }
        connectModes()
        EmojiCatalog.preload()
        CalendarAgenda.shared.onChange = { [weak self] in self?.refresh() }
        // The roles' apps and the clipboard destination are cached for the search (see `preferredApps`);
        // a change to one of the choices drops the cache, and so does an app folder that changed (see `finishApps`).
        for drop in [
            settings.$terminalApp.mapVoid(), settings.$editorApp.mapVoid(), settings.$browserApp.mapVoid(),
            settings.$clipboardHandler.mapVoid(), settings.$clipboardApp.mapVoid(), settings.$clipboardURL.mapVoid(),
        ] {
            drop.sink { [weak self] _ in self?.invalidateResolvedApps() }
                .store(in: &cancellables)
        }
        refresh()
    }

    /// Kicks off the initial scans in the worker. Called after the panel and its subscriptions exist,
    /// so their publications are heard from the start.
    func startCatalogLoading() {
        reloadApps()
        reloadCommands()
        reloadScripts()
        Task { @concurrent [weak self, scanner] in
            let panes = await scanner.scanSettingsPanes()
            await self?.finishSettingsPanes(panes)
        }
    }

    @MainActor
    private func finishSettingsPanes(_ panes: [SystemSettingsPane]) {
        settingsPanes = panes
        // Nothing to redraw without a query: the panes are only searched for.
        if !query.isEmpty {
            refresh()
        }
    }

    @discardableResult
    func reloadSSHHosts() -> Task<Void, Never> {
        Task { @concurrent [weak self, scanner] in
            let hosts = await scanner.scanSSHHosts()
            await self?.finishSSHHosts(hosts)
        }
    }

    @MainActor
    private func finishSSHHosts(_ hosts: [SSHHost]) {
        guard hosts != sshHosts else { return }
        sshHosts = hosts
        // Nothing to redraw without a query: the hosts are only searched for.
        if !query.isEmpty {
            refresh()
        }
    }

    func reloadCommands() {
        commandsGeneration += 1
        let generation = commandsGeneration
        // Read once, here: the worker never sees the mutable settings object.
        let includeRaycast = settings.includeRaycastExtensions
        isLoadingCatalog = true
        commandsTask = Task { @concurrent [weak self, scanner] in
            let commands = await scanner.scanCommands(includeRaycast: includeRaycast)
            await self?.finishCommands(generation: generation, commands: commands)
        }
    }

    func reloadScripts() {
        scriptsGeneration += 1
        let generation = scriptsGeneration
        isLoadingCatalog = true
        scriptsTask = Task { @concurrent [weak self, scanner] in
            let scan = await scanner.scanScripts()
            await self?.finishScripts(generation: generation, scan: scan)
        }
    }

    /// Publication happens on the main actor; a stale generation is dropped without touching state,
    /// so rescans keep the previous results visible while they run.
    @MainActor
    private func finishScripts(generation: Int, scan: ScriptScan) {
        guard generation == scriptsGeneration else { return }
        scriptsTask = nil
        // The folder is scanned each time the panel opens and is nearly always the same: then nothing is redrawn.
        let isSame = hasLoadedScripts && scan.commands == allScripts && scan.failures == scriptFailures
        hasLoadedScripts = true
        isLoadingCatalog = !hasLoadedApps || !hasLoadedCommands || !hasLoadedScripts
        guard !isSame else { return }
        allScripts = scan.commands
        scriptFailures = scan.failures
        refresh()
    }

    /// Joins the script scan in flight, following any newer request that replaces it while the
    /// caller waits.
    @MainActor
    func waitForScripts() async {
        while let task = scriptsTask {
            await task.value
        }
    }

    /// Publication happens on the main actor; a stale generation is dropped without touching state,
    /// so rescans keep the previous results visible while they run.
    @MainActor
    private func finishApps(generation: Int, apps newApps: [AppEntry]) {
        guard generation == appsGeneration else { return }
        appsTask = nil
        hasLoadedApps = true
        isLoadingCatalog = !hasLoadedApps || !hasLoadedCommands || !hasLoadedScripts
        apps = newApps
        // What is installed decides the roles' fallbacks, so a change resolves them again.
        invalidateResolvedApps()
        Log.catalog.info("Applications scanned: \(newApps.count)")
        refresh()
    }

    @MainActor
    private func finishCommands(generation: Int, commands newCommands: [ExtensionCommand]) {
        guard generation == commandsGeneration else { return }
        commandsTask = nil
        hasLoadedCommands = true
        isLoadingCatalog = !hasLoadedApps || !hasLoadedCommands || !hasLoadedScripts
        allCommands = newCommands
        Log.catalog.info("Extension commands scanned: \(newCommands.count)")
        refresh()
    }

    /// Joins the command scan in flight, following any newer request that replaces it while the
    /// caller waits. Suspending leaves the main actor free, and results are published before the
    /// joined task finishes, so a caller that returns sees the current catalog or nothing pending.
    @MainActor
    func waitForCommands() async {
        while let task = commandsTask {
            await task.value
        }
    }

    func refresh() {
        let started = Date()
        searchedQuery = query
        defer {
            if Date().timeIntervalSince(started) >= Log.slowSearch {
                Log.search.warning("Slow search: \(Log.milliseconds(since: started)) ms for \(query.count) characters, \(results.count) rows")
            }
        }
        let context = searchContext()
        // A source that is switched on also answers to its keyword, after the scopes that are always there.
        let enabled = RootSearch.enabled(sources, in: settings.searchSources)
        guard let match = RootSearch.scope(in: context, scopes: ClipboardApps.scopes(scopes, handler: settings.clipboardHandler) + enabled) else {
            activeScope = nil
            scopeUpdates.cancel()
            selection = 0
            // The list is shown at once; a source's rows join it when they arrive.
            sourceSearch.search(context, sources: enabled) { [weak self] in self?.showSourceRows() }
            isAwaitingResults = sourceSearch.isSearching
            results = RootSearch.results(for: context, sources: sourceSearch.rows)
            return
        }
        // A refresh that is not a new query, such as a rescan or a favorite, leaves a running scope alone.
        guard match.query != activeScope?.query else { return }
        sourceSearch.cancel()
        activeScope = match
        selection = 0
        results = match.rows(match.scope.results(for: match.text, context: context))
        isAwaitingResults = scopeUpdates.follow(match.scope.updates(for: match.text, context: context)) { [weak self] items in
            self?.showScoped(match.rows(items))
        } finish: { [weak self] in
            self?.isAwaitingResults = false
        }
    }

    /// Rows that arrived after the query was typed. A selection the user moved stays on its row.
    private func showScoped(_ rows: [RootResult]) {
        let selected = selection == 0 ? nil : selectedRootItem?.id
        results = rows
        selection = selected.flatMap { id in rows.firstIndex { $0.id == id } } ?? min(selection, max(rows.count - 1, 0))
    }

    /// A source's rows arrived below the ranked ones. The selection stays on the row it was on.
    private func showSourceRows() {
        let selected = selectedRootItem?.id
        isAwaitingResults = sourceSearch.isSearching
        results = RootSearch.results(for: searchContext(), sources: sourceSearch.rows)
        selection = selected.flatMap { id in results.firstIndex { $0.id == id } } ?? min(selection, max(results.count - 1, 0))
    }

    /// Everything the search providers may know, read once per search.
    private func searchContext() -> SearchContext {
        var context = SearchContext(query: query)
        context.favorites = settings.favorites
        context.hidden = Set(settings.hiddenResults.keys)
        context.emojiSkinTone = settings.emojiSkinTone
        context.shell = settings.shell
        context.searchSources = settings.searchSources
        context.checkpoints = checkpoints
        context.reminderLists = context.trimmed.lowercased().hasPrefix(ReminderDraft.keyword + " ") ? reminding.lists() : []
        context.timers = runningTimers.all
        context.focusShortcut = settings.focusShortcut
        context.aliases = settings.aliases
        context.notesApp = settings.notesApp
        context.frecency = { [usage] in usage.frecency(of: $0) }
        context.commands = commands
        context.scripts = allScripts
        context.apps = apps
        context.thawActions = Thaw.actions()
        context.preferredApps = preferredApps
        context.clipboardDestination = clipboardDestination
        context.settingsPanes = settingsPanes
        context.sshHosts = sshHosts
        context.shortcuts = shortcutsForSearch
        context.snippets = SnippetStore.shared.snippets
        context.quicklinks = QuicklinkStore.shared.links
        context.menuBarItemNames = settings.menuBarItemNames
        context.canAskAI = !query.isEmpty && canAskAI()
        return context
    }

    func alias(for item: RootItem) -> String? {
        RootSearch.alias(for: item, aliases: settings.aliases)
    }

    func isFavorite(_ item: RootItem) -> Bool {
        settings.favorites.contains(item.id)
    }

    func toggleFavorite(_ item: RootItem) {
        if case .searchFiles = item {
            // The fallback row names a query, not a thing: it has no favorites entry.
            return
        }
        if item.isScopeResult {
            return
        }
        if case .askAI = item {
            return
        }
        if let index = settings.favorites.firstIndex(of: item.id) {
            settings.favorites.remove(at: index)
            showHUD(String(localized: "Removed from Favorites", bundle: .floe))
        } else {
            settings.favorites.append(item.id)
            showHUD(String(localized: "Added to Favorites", bundle: .floe))
        }
        refresh()
    }

    /// Opens an app, or hides it if it's already in front, like a per-app hotkey in Thaw.
    func toggleApp(_ app: AppEntry) {
        usage.recordUse(of: RootItem.app(app).id)
        if let running = NSWorkspace.shared.frontmostApplication, running.bundleURL?.standardizedFileURL == app.url.standardizedFileURL {
            running.hide()
        } else {
            NSWorkspace.shared.openWithoutWaiting(app.url)
        }
    }

    func reloadApps() {
        appsGeneration += 1
        let generation = appsGeneration
        isLoadingCatalog = true
        appsTask = Task { @concurrent [weak self, scanner] in
            let apps = await scanner.scanApps()
            await self?.finishApps(generation: generation, apps: apps)
        }
    }

    /// `FLOE_AUTORUN=extension/command` opens a command at startup, for screenshots and debugging.
    /// It waits for the command load that is current when it runs and attempts the command once;
    /// later rescans never rerun it.
    func autorun(
        target: String? = ProcessInfo.processInfo.environment["FLOE_AUTORUN"],
        launch: ((ExtensionCommand) -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            await self?.waitForCommands()
            guard let self, !didAutorun else { return }
            didAutorun = true
            guard let target, let command = commands.first(where: { $0.id == target }) else { return }
            if let launch {
                launch(command)
            } else {
                run(command)
            }
        }
    }

    func activate(_ item: RootItem) {
        if case let .emoji(entry) = item {
            pasteEmojiResult(entry)
            return
        }
        if item.isScopeResult {
            // Found just now and gone next time: opening one records no frecency entry.
            (scopeResultOpener ?? openScopeResult)(item)
            return
        }
        if case let .askAI(question) = item {
            // Nothing about a question is kept: no usage record either.
            openAskAI(question)
            return
        }
        if case .searchFiles = item {
            // A transient row for the query text: opening it records no frecency entry.
        } else {
            usage.recordUse(of: item.id)
        }
        rememberQuery()
        switch item {
        case let .app(app):
            NSWorkspace.shared.openWithoutWaiting(app.url)
            hidePanel()
            reset()
        case let .command(command):
            run(command)
        case let .script(script):
            let text = script.argumentsText(in: query) ?? ""
            run(script, argumentStrings: ScriptRunner.splitArguments(text))
        case .menuBarSearch:
            openMenuBarSearch()
        case .emojiSearch:
            query = EmojiSearchProvider.prefix
            focusToken += 1
        case .clipboardHistory, .clipboardApp:
            openClipboardHistory()
        case .fileSearch:
            openFileSearch(with: query)
        case let .searchFiles(searchQuery):
            openFileSearch(with: searchQuery)
        case .settings:
            hidePanel()
            openSettings(nil)
        case let .quicklink(link, queryText, _, _):
            if let destination = url(for: link, query: queryText) {
                openLink(destination)
            }
            hidePanel()
            reset()
        case let .system(command):
            runSystemCommand(command)
        case let .note(action, text):
            hidePanel()
            reset()
            writeNote(action, text: text)
        case let .finderSelection(role, app):
            openFinderSelection(in: role, app: app)
        case let .thaw(action):
            hidePanel()
            reset()
            if !Thaw.perform(action) {
                showHUD(String(localized: "Thaw isn't installed", bundle: .floe))
            }
        case let .sshHost(host, terminal):
            hidePanel()
            reset()
            SSHConnection.connect(to: host, terminal: terminal, using: sshConnector) { [weak self] in self?.showHUD($0) }
        case let .shortcut(shortcut):
            run(shortcut)
        case let .settingsPane(pane):
            if let url = pane.url {
                NSWorkspace.shared.openWithoutWaiting(url)
            }
            hidePanel()
            reset()
        case let .snippet(snippet):
            paste(text: SnippetStore.shared.expanded(snippet))
        case let .event(event):
            if let destination = event.meetingURL ?? event.calendarURL {
                openLink(destination)
            }
            hidePanel()
            reset()
        case let .calculator(_, result, error, _):
            copyCalculation(result, error: error)
        default:
            // A scope's rows were opened before the switch. What is left is a row that came later.
            openLater(item)
        }
    }

    /// Risky commands ask first; the panel goes away before anything runs.
    private func runSystemCommand(_ command: SystemCommand) {
        hidePanel()
        reset()
        if let question = command.confirmation {
            guard Confirm.destructive(command.title, detail: question, button: command.title) else { return }
        }
        if let flip = command.flip {
            showHUD(flip())
            return
        }
        if let control = command.music {
            controlMusic(control)
            return
        }
        command.perform()
    }

    /// Copies an emoji without pasting; ⌘↵ on a result.
    func copyEmojiResult(_ entry: EmojiResult) {
        usage.recordUse(of: entry.id)
        NSPasteboard.general.copy(entry.character)
        showHUD(String(localized: "Copied \(entry.character)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
    }

    /// Pastes an emoji into the frontmost app: onto the clipboard plus a ⌘V once the panel is
    /// gone, when Accessibility access is granted; otherwise the copy plus a "Copied" HUD.
    func pasteEmojiResult(_ entry: EmojiResult) {
        usage.recordUse(of: entry.id)
        NSPasteboard.general.copy(entry.character)
        guard AXIsProcessTrusted() else {
            showHUD(String(localized: "Copied", bundle: .floe, comment: "Shown briefly after something was put on the clipboard."))
            return
        }
        hidePanel()
        reset()
        // Pressed once the panel is gone, so the keystroke lands in the app the user came from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ClipboardHistoryStore.simulatePaste()
        }
    }

    /// Runs a script command with the given argv. Arguments come from the text typed after its
    /// title; output follows its mode: a window for fullOutput, a HUD for compact and inline,
    /// nothing for silent. Failures show a HUD with the last stderr line.
    func run(_ script: ScriptCommand, argumentStrings: [String] = []) {
        if script.needsConfirmation {
            let alert = NSAlert()
            alert.messageText = String(localized: "Run \(script.title)?", bundle: .floe, comment: "The placeholder is the name of a script.")
            alert.informativeText = script.displayPackage
            alert.addButton(withTitle: String(localized: "Run", bundle: .floe, comment: "A verb on a button: run the shortcut or script."))
            alert.addButton(withTitle: String(localized: "Cancel", bundle: .floe))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        usage.recordUse(of: RootItem.script(script).id)
        hidePanel()
        reset()
        Task { [weak self] in
            let result: ShellResult
            do {
                result = try await ScriptRunner.run(script, arguments: argumentStrings)
            } catch {
                await MainActor.run { [weak self] in
                    self?.showHUD(String(localized: "\(script.title) failed: \(error.localizedDescription)", bundle: .floe, comment: "The first placeholder is the name of a script, the second is the reason."))
                }
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard result.succeeded else {
                    let line = ScriptRunner.lastLine(result.errorOutput) ?? ScriptRunner.lastLine(result.output)
                        ?? String(localized: "exit code \(result.status)", bundle: .floe, comment: "The reason a script failed, when it printed nothing. The placeholder is a number.")
                    showHUD(String(localized: "\(script.title) failed: \(line)", bundle: .floe, comment: "The first placeholder is the name of a script, the second is the reason."))
                    return
                }
                switch script.mode {
                case .silent:
                    break
                case .inline, .compact:
                    let line = ScriptRunner.lastLine(result.output) ?? String(localized: "Done (script finished)", defaultValue: "Done", bundle: .floe, comment: "Shown briefly when a script finished and printed nothing.")
                    showHUD(line)
                case .fullOutput:
                    ScriptOutputWindow.show(title: script.title, output: result.trimmedOutput)
                }
            }
        }
    }

    /// Runs a command, first asking for missing required preferences and then for its arguments.
    func run(_ command: ExtensionCommand, arguments: [String: Any]? = nil) {
        let missing = PreferenceStore.missingRequired(for: command)
        // Running a menu-bar command is choosing whether it has a status item.
        if command.mode == "menu-bar", missing.isEmpty {
            toggleMenuBarCommand(command)
            return
        }
        if let session {
            end(session)
        }
        if !missing.isEmpty {
            beginSetup(SetupRequest(command: command, kind: .preferences, fields: command.preferences))
        } else if arguments == nil, !command.arguments.isEmpty {
            beginSetup(SetupRequest(command: command, kind: .arguments, fields: command.arguments))
        } else {
            if command.mode == "view" {
                showPanel()
            }
            launch(command, arguments: arguments ?? [:])
        }
    }

    private func launch(_ command: ExtensionCommand, arguments: [String: Any]) {
        Log.extensions.info("Running \(command.extensionName)/\(command.name) (\(command.mode))")
        let session = ExtensionSession(command: command, arguments: arguments)
        session.onMessage = { [weak self, weak session] message in
            guard let self, let session else { return }
            self.handle(message, from: session)
        }
        self.session = session
        session.start()
        sourceWatcher = HotReload.watcher(for: command) { [weak self, weak session] paths in
            guard let self, let session else { return }
            self.reload(session, changed: paths)
        }
    }

    /// A file of the open command's extension was saved: runs the command again as `retry` does.
    /// A panel that is hidden while its command waits to be resumed stays hidden.
    private func reload(_ watched: ExtensionSession, changed paths: [String]) {
        guard session === watched else { return }
        if HotReload.changesManifest(paths) {
            reloadCommands()
        }
        if pendingReset == nil {
            retry()
        } else {
            end(watched)
            launch(watched.command, arguments: watched.arguments)
        }
    }

    private func handle(_ message: [String: Any], from session: ExtensionSession) {
        switch message["type"] as? String {
        case "exit", "popToRoot":
            let wasBackground = session.command.mode != "view"
            end(session)
            if wasBackground {
                hidePanel()
            }
        case "crashed" where session.command.mode != "view":
            end(session)
            showHUD(String(localized: "\(session.command.title) failed", bundle: .floe, comment: "The placeholder is the name of a command."))
        case "close":
            hidePanel()
        case "hud":
            showHUD(message["title"] as? String ?? "")
            hidePanel()
        case "copy":
            copy(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
        case "paste":
            paste(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
        case "open":
            open(message["target"] as? String ?? "", application: message["application"] as? String)
        case "openPreferences":
            hidePanel()
            openSettings(session.command.extensionName)
        default:
            break
        }
    }

    func end(_ session: ExtensionSession) {
        // Trailing messages (a HUD after closeMainWindow, say) still need to be read.
        session.stop(after: 0.5)
        if self.session === session {
            self.session = nil
            sourceWatcher = nil
            focusToken += 1
        }
    }

    /// The panel closed. The open command survives for the configured delay, so reopening resumes it.
    func panelDidHide() {
        pendingReset?.cancel()
        let delay = settings.popToRootDelay
        guard delay > 0, session != nil || setup != nil else {
            reset()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.reset() }
        pendingReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: work)
    }

    func panelWillShow() {
        pendingReset?.cancel()
        pendingReset = nil
        reloadScripts()
        reloadSSHHosts()
        reloadShortcuts()
        // A grant made in System Settings with no request from Floe is noticed here.
        menuBarSearch.warm()
        ExchangeRateUpdater.shared.refreshIfStale()
        reloadCheckpoints()
    }

    /// Runs the command that failed again, with the same arguments.
    func retry() {
        guard let session else { return }
        let command = session.command
        let arguments = session.arguments
        end(session)
        run(command, arguments: arguments)
    }

    func copyFailure() {
        guard let session, let failure = session.failure else { return }
        copy(text: "\(session.command.extensionTitle) › \(session.command.title)\n\(failure.message)\n\n\(failure.details)")
        showHUD(String(localized: "Copied error details", bundle: .floe))
    }

    /// Back to the root search, ending any open command.
    func reset() {
        pendingReset?.cancel()
        pendingReset = nil
        if let session {
            end(session)
        }
        setup = nil
        isSearchingMenuBar = false
        isShowingClipboardHistory = false
        isSearchingFiles = false
        fileSearch.cancel()
        closeAskAI()
        recalledQuery = nil
        query = ""
    }

    private func copy(text: String, html: String? = nil, file: String? = nil) {
        PasteboardContent.write(text: text, html: html, file: file)
    }

    func paste(text: String, html: String? = nil, file: String? = nil) {
        PasteboardContent.write(text: text, html: html, file: file)
        if AXIsProcessTrusted() {
            hidePanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                KeySimulation.paste()
            }
        } else {
            showHUD(String(localized: "Copied. Press ⌘V to paste.", bundle: .floe))
            hidePanel()
        }
    }

    /// Handles `open`, `copy`, `paste` and `hud` from sessions the panel doesn't own (menu-bar extras,
    /// background runs). Background runs never open the panel.
    func handleBackgroundMessage(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "hud":
            showHUD(message["title"] as? String ?? "")
        case "copy":
            copy(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
        case "paste":
            // A background run never takes the keyboard from the user; it only copies.
            copy(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
            showHUD(String(localized: "Copied. Press ⌘V to paste.", bundle: .floe))
        case "open":
            open(message["target"] as? String ?? "", application: message["application"] as? String)
        default:
            break
        }
    }

    private func open(_ target: String, application: String?) {
        let url = URL(string: target).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        if let application, let app = applicationURL(for: application) {
            linkOpener.open(url, app)
        } else {
            openLink(url)
        }
    }

    /// Extensions name an app by path, bundle identifier or display name.
    private func applicationURL(for application: String) -> URL? {
        if (application as NSString).isAbsolutePath {
            return URL(fileURLWithPath: application)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: application)
            ?? apps.first { $0.name.caseInsensitiveCompare(application) == .orderedSame }?.url
    }
}

private extension Published.Publisher {
    /// The changes only, not the value: what a cache drop listens for.
    func mapVoid() -> AnyPublisher<Void, Never> {
        map { _ in }.eraseToAnyPublisher()
    }
}
