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
        didSet {
            refusal.clear()
            typing.changed { [weak self] in self?.refresh() }
        }
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
    let pointerRest = PointerRest()
    let refusal = ReturnRefusal()

    private func tellTheSelectedRow() {
        rowSelection.select(results.indices.contains(selection) ? results[selection].id : nil)
    }

    /// Runs extension commands and keeps the one on screen.
    let runner = ExtensionRunner()
    /// The setup form on screen, if any. What is typed into it is `setupForm`'s.
    @Published var setup: SetupRequest?
    /// Not published: typing in the form redraws the form only.
    let setupForm = SetupFormModel()
    /// Bumped whenever the panel is shown so the search field can take focus again.
    @Published var focusToken = 0
    /// The apps, commands, scripts, panes and hosts the search finds; the model refreshes when a part changes.
    let catalog: CatalogStore

    /// True while the panel shows the file search instead of the root search.
    @Published var isSearchingFiles = false
    /// The file search's own state. Not published: its changes redraw its view only.
    lazy var fileSearch = FileSearchModel()

    /// True while the panel shows the menu bar item search instead of the root search.
    @Published var isSearchingMenuBar = false
    /// True while the panel shows the clipboard history instead of the root search.
    @Published var isShowingClipboardHistory = false
    /// The clipboard history view's own state. Not published: its changes redraw its view only.
    lazy var clipboardHistory = ClipboardHistoryModel(usage: usage) { [unowned self] in clipboard }
    /// The clipboard history the panel shows, recorded since Floe started.
    let clipboard: ClipboardHistoryStore
    /// The notes of the user's folder, while the panel shows them instead of the root search.
    @Published var noteDesk: NoteDeskModel?
    /// The last save of the notes view closed last: true once it is written.
    var noteDeskSave: Task<Bool, Never>?
    /// The question on screen and its answer, while the panel shows them instead of the root search.
    @Published var askAI: AskAIModel?
    /// A question asked before something that cannot be taken back, over whatever the panel shows.
    @Published var question: PanelQuestion?
    /// Answers the question. A test replaces it: the real thing reaches the chosen AI source.
    var askAIRequest: AskAIModel.Request = AskAIModel.live
    /// Whether an AI source can answer. The app delegate sets it; without one no Ask AI row is offered.
    var canAskAI: () -> Bool = { false }
    /// The menu bar item search's own state. Not published: its changes redraw its view only.
    lazy var menuBarSearch = MenuBarSearchModel(settings: settings)
    /// The front app's menu commands, while the panel shows them instead of the root search.
    @Published var menuItemSearch: MenuItemSearchModel?
    /// What that search asks of the system. A test replaces it: the real thing reads another app's menus.
    var menuItemEnvironment = MenuItemSearchModel.Environment()

    /// What the model asks of the process around it.
    var panelHost = PanelHost()

    /// The scope whose rows are on screen, when the query names one.
    var activeScope: ScopeMatch?
    /// True while a scope's rows are still on their way.
    @Published private(set) var isAwaitingResults = false
    /// Stands in for opening a scope's row. Tests set it: the real thing pastes and clicks outside the launcher.
    var scopeResultOpener: ((RootItem) -> Void)?
    private let scopes: [any SearchScope]
    private let scopeUpdates = SearchUpdates()
    /// The optional sources, and the rows they found for the ordinary search on screen.
    private let sources: [any SearchSource]
    private let sourceSearch = SourceSearch()
    /// What the providers answered for the ordinary search on screen, which rows found later join.
    var rootAnswer: RootSearchAnswer?
    lazy var definitionSearch = DefinitionSearch()
    lazy var calculatorSearch = CalculatorSearch()

    let settings: AppSettings
    /// The apps the roles resolve to, kept until something they depend on changes.
    let resolvedApps: ResolvedApps
    private var cancellables: Set<AnyCancellable> = []
    var clipboardOpener = ClipboardOpener.system
    var linkOpener = LinkOpener.system
    let usage: UsageStore
    /// The launcher's features, each handed what it asks of the launcher.
    lazy var features = LauncherFeatures(model: self)
    /// Where in the remembered searches the field stands, while the Up arrow walks back through them.
    var recalledQuery: Int?
    private var didAutorun = false
    private var pendingReset: DispatchWorkItem?
    private(set) var isPanelShown = false
    /// Construction never scans: `startCatalogLoading()` fills the catalog after subscribers are wired.
    init(
        scanner: any CatalogScanning = CatalogLoader(),
        settings: AppSettings = .shared,
        usage: UsageStore = .shared,
        snapshot: CatalogSnapshot? = nil,
        scopes: [any SearchScope]? = nil,
        sources: [any SearchSource]? = nil,
        clipboard: ClipboardHistoryStore? = nil
    ) {
        let clipboard = clipboard ?? .detached()
        self.clipboard = clipboard
        self.scopes = scopes ?? RootSearch.standardScopes { clipboard.entries }
        self.sources = sources ?? RootSearch.standardSources()
        self.settings = settings
        self.usage = usage
        catalog = CatalogStore(scanner: scanner, settings: settings, snapshot: snapshot)
        resolvedApps = ResolvedApps(settings: settings)
        catalog.onChange = { [weak self] in self?.catalogChanged($0) }
        connectRunner()
        connectModes()
        // Views read the catalog's loading state and the open command through the model, so their changes redraw it.
        catalog.$isLoading.removeDuplicates().dropFirst().map { _ in () }
            .merge(with: runner.$session.dropFirst().map { _ in () })
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        EmojiCatalog.preload()
        CalendarAgenda.shared.onChange = { [weak self] in self?.refresh() }
        resolvedApps.followChoices()
        refresh()
    }

    /// Recomputes the search's results.
    func refresh() {
        let started = Date()
        searchedQuery = query
        defer {
            if Date().timeIntervalSince(started) >= Log.slowSearch {
                Log.search.warning("Slow search: \(Log.milliseconds(since: started)) ms for \(query.count) characters, \(results.count) rows")
            }
        }
        var context = searchContext()
        // A source that is switched on also answers to its keyword, after the scopes that are always there.
        let enabled = RootSearch.enabled(sources, in: settings.searchSources)
        guard let match = RootSearch.scope(in: context, scopes: ClipboardApps.scopes(scopes, handler: settings.clipboardHandler, parked: settings.clipboardHistoryIsParked) + enabled) else {
            activeScope = nil
            scopeUpdates.cancel()
            selection = 0
            // The list is shown at once; a source's rows join it when they arrive.
            sourceSearch.search(context, sources: enabled) { [weak self] in self?.showSourceRows() }
            definitionSearch.search(context) { [weak self] in self?.showLateAnswers() }
            calculatorSearch.search(context) { [weak self] in self?.showLateAnswers() }
            context.definition = definitionSearch.definition
            context.calculation = calculatorSearch.row
            // No spinner for the calculator: its answer is almost always a moment away.
            isAwaitingResults = sourceSearch.isSearching || definitionSearch.isSearching
            let answer = RootSearchAnswer(for: context)
            rootAnswer = answer
            results = answer.results(sources: sourceSearch.rows)
            return
        }
        // A refresh that is not a new query, such as a rescan or a favorite, leaves a running scope alone.
        guard match.query != activeScope?.query else { return }
        sourceSearch.cancel()
        definitionSearch.cancel()
        calculatorSearch.cancel()
        rootAnswer = nil
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

    /// A source's rows arrived below the ranked ones, or a late answer above them. The providers are not asked
    /// again, and the selection stays on the row it was on.
    func showSourceRows() {
        guard let rootAnswer else { return }
        let selected = selectedRootItem?.id
        isAwaitingResults = sourceSearch.isSearching || definitionSearch.isSearching
        results = rootAnswer.results(sources: sourceSearch.rows)
        selection = selected.flatMap { id in results.firstIndex { $0.id == id } } ?? min(selection, max(results.count - 1, 0))
    }

    /// `FLOE_AUTORUN=extension/command` opens a command at startup, for screenshots and debugging.
    /// It waits for the command load that is current when it runs and attempts the command once;
    /// later rescans never rerun it.
    func autorun(
        target: String? = ProcessInfo.processInfo.environment["FLOE_AUTORUN"],
        launch: ((ExtensionCommand) -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            await self?.catalog.waitForCommands()
            guard let self, !didAutorun else { return }
            didAutorun = true
            guard let target, let command = commands.first(where: { $0.id == target }) else { return }
            if let launch {
                launch(command)
            } else {
                runner.run(command)
            }
        }
    }

    /// The panel closed. The open command survives for the configured delay, so reopening resumes it.
    func panelDidHide() {
        isPanelShown = false
        // Closing the panel is no answer to go ahead on.
        question = nil
        pendingReset?.cancel()
        let delay = settings.popToRootDelay
        guard delay > 0, runner.session != nil || setup != nil else {
            reset()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.reset() }
        pendingReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: work)
    }

    /// Whether the panel is hidden with its command kept for the user to come back to.
    var isWaitingToResume: Bool {
        pendingReset != nil
    }

    /// Cancels the deferred reset. What is read again for the search waits for panelDidShow.
    func panelWillShow() {
        isPanelShown = true
        pendingReset?.cancel()
        pendingReset = nil
    }

    /// Back to the root search, ending any open command.
    func reset() {
        pendingReset?.cancel()
        pendingReset = nil
        runner.endOpenCommand()
        setup = nil
        isSearchingMenuBar = false
        menuItemSearch = nil
        isShowingClipboardHistory = false
        isSearchingFiles = false
        fileSearch.cancel()
        closeNoteDesk()
        closeAskAI()
        recalledQuery = nil
        query = ""
    }
}
