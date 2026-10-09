//
//  Settings.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import Foundation
import SwiftUI

/// Launcher-wide settings, persisted as one JSON blob in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultToggleHotkey = KeyCombination(key: .space, modifiers: [.control, .option])

    @Published var toggleHotkey: KeyCombination? = defaultToggleHotkey
    /// Keyed by `RootItem.settingsKey`: a command's id, or "app:" and the app's path.
    @Published var commandHotkeys: [String: KeyCombination] = [:]
    /// Keyed by `RootItem.settingsKey`.
    @Published var aliases: [String: String] = [:]
    /// `RootItem.id`s, in the order they're shown.
    @Published var favorites: [String] = []
    /// Results taken out of the search: `RootItem.id` to the title it had, which Settings lists it by.
    @Published var hiddenResults: [String: String] = [:]
    @Published var emojiSkinTone = EmojiSkinTone.none
    /// Extension names.
    @Published var disabledExtensions: Set<String> = []
    /// `ExtensionCommand.id`s switched off one by one, inside an extension that is on.
    @Published var disabledCommands: Set<String> = []
    @Published var includeRaycastExtensions = true
    /// Seconds a closed panel keeps the open command before going back to the root search; 0 resets at once.
    @Published var popToRootDelay = 90
    /// Show Floe's icon in the Dock; off, it lives only in the menu bar.
    @Published var showInDock = false
    /// The welcome window was finished or skipped once, so it does not open on later launches.
    @Published var hasSeenOnboarding = false
    /// Keep the menu bar search's query between showings, like Thaw's "Remember last search".
    @Published var rememberMenuBarQuery = false
    /// Whether copies are saved to the clipboard history.
    @Published var clipboardHistoryEnabled = true
    @Published var diagnosticLogging = false
    /// The search sources that are switched on, by `SearchSource.id`. All are off until switched on in Privacy.
    @Published var searchSources: Set<String> = []
    /// The menu-bar commands that have a status item, by command id. A command is added by running it.
    @Published var menuBarCommands: Set<String> = []
    /// The notes role's choice: where a note typed into the search goes, and the link for "Another App".
    @Published var notesApp = NotesApp.appleNotes
    @Published var notesURLTemplate = ""
    /// The folder notes are written into when the notes app is a folder of notes.
    @Published var notesFolder = ""
    /// The apps folders and files are opened in; nil is the role's default (see AppRole).
    @Published var terminalApp: AppChoice?
    @Published var editorApp: AppChoice?
    /// The browser web links open in; nil is whatever macOS opens them with (see `Browsers`).
    @Published var browserApp: AppChoice?
    /// The clipboard role's choice: Floe's own history, an app, or the link that opens an app's history.
    @Published var clipboardHandler = ClipboardHandler.floe
    @Published var clipboardApp: AppChoice?
    @Published var clipboardURL = ""
    /// Names given to menu bar items with Edit Name, keyed by `MenuBarExtra.id`.
    @Published var menuBarItemNames: [String: String] = [:]
    /// True while a hotkey recorder is listening, so the registry can stand down.
    @Published var isRecordingHotkey = false
    /// Thaw-style appearance for the launcher panel: a tint over the glass, an
    /// optional border, and a shaped drop shadow. Like Thaw's isDynamic switch,
    /// the tint can follow the system appearance with separate light and dark
    /// values, or stay the same in both.
    @Published var launcherGlass = LauncherGlass()
    /// While on, the launcher draws Thaw's menu bar look and leaves the appearance settings here as they are.
    @Published var followsThawAppearance = false
    /// What Thaw last answered, by colour scheme. `ThawAppearanceFollower` keeps these; they are not saved with the settings.
    @Published var thawAppearances: [ThawAppearance.Scheme: ThawAppearance] = [:]
    /// Extended always shows the list; compact is the search bar alone until something is typed.
    @Published var launcherLayout = LauncherLayout.extended
    @Published var searchFieldShape = SearchFieldShape.rounded
    /// The search field and the results as two pieces of glass, in either layout.
    @Published var separatesSearchField = false
    @Published var launcherTintIsDynamic = false
    @Published var launcherTintLight = LauncherTint()
    @Published var launcherTintDark = LauncherTint()
    @Published var launcherBorder = LauncherBorder()
    @Published var launcherShowsBorder = false
    @Published var launcherShowsShadow = false
    /// What answers an extension's `AI.ask`, and where the API is when that is the choice.
    /// The API's key is in the Keychain (`AIEndpoint.keychainAccount`).
    @Published var aiSource = AISource.tools
    @Published var aiBaseURL = AIEndpoint.defaultBaseURL
    @Published var aiModel = ""
    /// The command line tool that answers when the source is the tools; nil is Automatic (see `AIEngine.resolve`).
    @Published var aiTool: AITool?
    /// The model typed for a tool that takes one, by `AITool.rawValue`. A tool without one uses its own default.
    @Published var aiToolModels: [String: String] = [:]
    /// Only use AI that runs on this Mac: a source that sends questions elsewhere refuses.
    @Published var aiOnThisMacOnly = false
    /// Whether a search that ended in something being opened is kept for the Up arrow to bring back.
    @Published var remembersSearches = true
    /// Whether a receipt is kept of what Floe did: commands run, files moved to the Trash, processes quit.
    @Published var keepsReceipts = true
    /// Whether what each extension reaches is recorded. Off, its reports are dropped and its process is told not to watch.
    @Published var recordsExtensionAccess = true
    /// The extensions lent a sign-in from this Mac, each as "extension/provider".
    @Published var lentSignIns: Set<String> = []
    @Published var shell = ShellSettings()
    /// Whether the calculator may download the European Central Bank's exchange rates. Off until the user says so.
    @Published var fetchesExchangeRates = false
    /// The name of the Shortcut that sets a Focus, which Toggle Focus and `focus 1 hour` run. Empty until the user names one.
    @Published var focusShortcut = ""
    /// Extensions pinned to a source other than the one above, by extension name.
    @Published var aiSourceByExtension: [String: AISource] = [:]

    /// Whether a command may be found and run: its extension is on, and so is the command.
    func isEnabled(_ command: ExtensionCommand) -> Bool {
        !disabledExtensions.contains(command.extensionName) && !disabledCommands.contains(command.id)
    }

    /// The switch on one command. It reads as off while its extension is off, and keeps its own value underneath.
    func enabledBinding(for command: ExtensionCommand) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(command) },
            set: { isOn in
                if isOn {
                    self.disabledCommands.remove(command.id)
                } else {
                    self.disabledCommands.insert(command.id)
                }
            }
        )
    }

    private struct Stored: Codable {
        var toggleHotkey: KeyCombination?
        var commandHotkeys: [String: KeyCombination]?
        var aliases: [String: String]?
        var disabledExtensions: Set<String>?
        var disabledCommands: Set<String>?
        var includeRaycastExtensions: Bool?
        var popToRootDelay: Int?
        var favorites: [String]?
        var hiddenResults: [String: String]?
        var emojiSkinTone: EmojiSkinTone?
        var rememberMenuBarQuery: Bool?
        var clipboardHistoryEnabled: Bool?
        var diagnosticLogging: Bool?
        var searchSources: Set<String>?
        var menuBarCommands: Set<String>?
        var notesApp: NotesApp?
        var notesURLTemplate: String?
        var notesFolder: String?
        var terminalApp: AppChoice?
        var editorApp: AppChoice?
        var browserApp: AppChoice?
        var clipboardHandler: ClipboardHandler?
        var clipboardApp: AppChoice?
        var clipboardURL: String?
        var menuBarItemNames: [String: String]?
        var showInDock: Bool?
        var hasSeenOnboarding: Bool?
        var launcherTint: LauncherTint?
        var launcherTintIsDynamic: Bool?
        var launcherTintLight: LauncherTint?
        var launcherTintDark: LauncherTint?
        var launcherBorder: LauncherBorder?
        var launcherShowsBorder: Bool?
        var launcherShowsShadow: Bool?
        var launcherGlass: LauncherGlass?
        var followsThawAppearance: Bool?
        var launcherLayout: LauncherLayout?
        var searchFieldShape: SearchFieldShape?
        var separatesSearchField: Bool?
        var aiSource: AISource?
        var aiBaseURL: String?
        var aiModel: String?
        var aiTool: AITool?
        var aiToolModels: [String: String]?
        var aiOnThisMacOnly: Bool?
        var remembersSearches: Bool?
        var keepsReceipts: Bool?
        var recordsExtensionAccess: Bool?
        var lentSignIns: Set<String>?
        var shell: ShellSettings?
        var fetchesExchangeRates: Bool?
        var focusShortcut: String?
        var aiSourceByExtension: [String: AISource]?
    }

    private static let defaultsKey = "settings"
    private let defaults: UserDefaults
    private var cancellable: AnyCancellable?
    /// Called after a save that changed what is stored. The process link sets it, to tell the other process.
    var onSaved: (() -> Void)?
    /// What the defaults held when this process last read or wrote them, to tell when another process has saved.
    private var seen: Data?
    /// This process's own settings as they were at that moment: what each side's changes are measured from.
    private var base: Data?
    private var isCapturingBase = false
    /// True while stored values are being taken in, so that is not mistaken for an edit to save.
    private var isReloading = false
    /// True from an edit until it is saved.
    private(set) var hasUnsavedChanges = false

    /// A test passes false for `savesAfterEdits`, so the moment of each save is its own to choose.
    init(defaults: UserDefaults = .standard, savesAfterEdits: Bool = true) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey), let stored = Self.read(data) {
            apply(stored)
            seen = data
        }
        captureBase()
        let edits = objectWillChange
            .filter { [weak self] in self?.isReloading == false }
            .handleEvents(receiveOutput: { [weak self] in self?.hasUnsavedChanges = true })
        cancellable = savesAfterEdits
            ? edits.debounce(for: .milliseconds(200), scheduler: RunLoop.main).sink { [weak self] in self?.save() }
            : edits.sink { /* saved by hand */ }
    }

    /// Takes what another process saved. Nothing is written back, so the other process hears no echo.
    func reload() {
        // Asked of the defaults server: this process's cached copy can trail another process's save.
        defaults.synchronize()
        guard let theirs = defaults.data(forKey: Self.defaultsKey), !SettingsMerge.isSame(theirs, seen) else { return }
        if hasUnsavedChanges {
            // The edit waiting here goes out now, on top of what the other process wrote.
            save()
        } else {
            take(theirs)
            seen = theirs
            captureBase()
        }
    }

    private func take(_ data: Data) {
        guard let stored = Self.read(data) else { return }
        isReloading = true
        apply(stored)
        isReloading = false
    }

    /// Runs `save()` as far as the encoding and keeps the result, so the list of settings stays in one place.
    private func captureBase() {
        isCapturingBase = true
        save()
        isCapturingBase = false
    }

    /// Stores this process's settings, with whatever another process changed since the last look kept.
    private func write(_ mine: Data) {
        guard !isCapturingBase else {
            base = mine
            return
        }
        hasUnsavedChanges = false
        let stored = defaults.data(forKey: Self.defaultsKey)
        var data = mine
        if let stored, !SettingsMerge.isSame(stored, seen) {
            data = SettingsMerge.merged(base: base, mine: mine, theirs: stored)
            take(data)
            captureBase()
        } else {
            base = mine
        }
        seen = data
        guard !SettingsMerge.isSame(data, stored) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
        onSaved?()
    }

    private func apply(_ stored: Stored) {
        toggleHotkey = stored.toggleHotkey
        commandHotkeys = stored.commandHotkeys ?? [:]
        aliases = stored.aliases ?? [:]
        disabledExtensions = stored.disabledExtensions ?? []
        disabledCommands = stored.disabledCommands ?? []
        includeRaycastExtensions = stored.includeRaycastExtensions ?? true
        popToRootDelay = stored.popToRootDelay ?? popToRootDelay
        favorites = stored.favorites ?? []
        hiddenResults = stored.hiddenResults ?? [:]
        emojiSkinTone = stored.emojiSkinTone ?? .none
        rememberMenuBarQuery = stored.rememberMenuBarQuery ?? false
        clipboardHistoryEnabled = stored.clipboardHistoryEnabled ?? true
        diagnosticLogging = stored.diagnosticLogging ?? false
        searchSources = stored.searchSources ?? []
        menuBarCommands = stored.menuBarCommands ?? []
        notesApp = stored.notesApp ?? notesApp
        notesURLTemplate = stored.notesURLTemplate ?? notesURLTemplate
        notesFolder = stored.notesFolder ?? ""
        terminalApp = stored.terminalApp
        editorApp = stored.editorApp
        browserApp = stored.browserApp
        clipboardHandler = stored.clipboardHandler ?? .floe
        clipboardApp = stored.clipboardApp
        clipboardURL = stored.clipboardURL ?? ""
        menuBarItemNames = stored.menuBarItemNames ?? [:]
        showInDock = stored.showInDock ?? false
        hasSeenOnboarding = stored.hasSeenOnboarding ?? false
        applyAppearance(stored)
        aiSource = stored.aiSource ?? aiSource
        aiBaseURL = stored.aiBaseURL ?? aiBaseURL
        aiModel = stored.aiModel ?? aiModel
        aiTool = stored.aiTool
        aiToolModels = stored.aiToolModels ?? [:]
        aiOnThisMacOnly = stored.aiOnThisMacOnly ?? aiOnThisMacOnly
        remembersSearches = stored.remembersSearches ?? true
        keepsReceipts = stored.keepsReceipts ?? true
        recordsExtensionAccess = stored.recordsExtensionAccess ?? true
        lentSignIns = stored.lentSignIns ?? []
        shell = stored.shell ?? ShellSettings()
        fetchesExchangeRates = stored.fetchesExchangeRates ?? false
        focusShortcut = stored.focusShortcut ?? ""
        aiSourceByExtension = stored.aiSourceByExtension ?? aiSourceByExtension
    }

    /// How the launcher looks, taken in apart from the rest so neither list grows past reading.
    private func applyAppearance(_ stored: Stored) {
        // A tint saved before light and dark variants existed becomes the light one.
        launcherTintLight = stored.launcherTintLight ?? stored.launcherTint ?? launcherTintLight
        launcherTintDark = stored.launcherTintDark ?? launcherTintDark
        launcherTintIsDynamic = stored.launcherTintIsDynamic ?? launcherTintIsDynamic
        launcherBorder = stored.launcherBorder ?? launcherBorder
        launcherShowsBorder = stored.launcherShowsBorder ?? launcherShowsBorder
        launcherShowsShadow = stored.launcherShowsShadow ?? launcherShowsShadow
        launcherGlass = stored.launcherGlass ?? launcherGlass
        followsThawAppearance = stored.followsThawAppearance ?? followsThawAppearance
        launcherLayout = stored.launcherLayout ?? launcherLayout
        searchFieldShape = stored.searchFieldShape ?? .rounded
        separatesSearchField = stored.separatesSearchField ?? false
    }

    /// Runs on its own shortly after any change; callable directly when the change must be on disk now.
    func save() {
        let stored = Stored(
            toggleHotkey: toggleHotkey,
            commandHotkeys: commandHotkeys,
            aliases: aliases,
            disabledExtensions: disabledExtensions,
            disabledCommands: disabledCommands,
            includeRaycastExtensions: includeRaycastExtensions,
            popToRootDelay: popToRootDelay,
            favorites: favorites,
            hiddenResults: hiddenResults,
            emojiSkinTone: emojiSkinTone,
            rememberMenuBarQuery: rememberMenuBarQuery,
            clipboardHistoryEnabled: clipboardHistoryEnabled,
            diagnosticLogging: diagnosticLogging,
            searchSources: searchSources,
            menuBarCommands: menuBarCommands,
            notesApp: notesApp,
            notesURLTemplate: notesURLTemplate,
            notesFolder: notesFolder,
            terminalApp: terminalApp,
            editorApp: editorApp,
            browserApp: browserApp,
            clipboardHandler: clipboardHandler,
            clipboardApp: clipboardApp,
            clipboardURL: clipboardURL,
            menuBarItemNames: menuBarItemNames,
            showInDock: showInDock,
            hasSeenOnboarding: hasSeenOnboarding,
            launcherTintIsDynamic: launcherTintIsDynamic,
            launcherTintLight: launcherTintLight,
            launcherTintDark: launcherTintDark,
            launcherBorder: launcherBorder,
            launcherShowsBorder: launcherShowsBorder,
            launcherShowsShadow: launcherShowsShadow,
            launcherGlass: launcherGlass,
            followsThawAppearance: followsThawAppearance,
            launcherLayout: launcherLayout,
            searchFieldShape: searchFieldShape,
            separatesSearchField: separatesSearchField,
            aiSource: aiSource,
            aiBaseURL: aiBaseURL,
            aiModel: aiModel,
            aiTool: aiTool,
            aiToolModels: aiToolModels,
            aiOnThisMacOnly: aiOnThisMacOnly,
            remembersSearches: remembersSearches,
            keepsReceipts: keepsReceipts,
            recordsExtensionAccess: recordsExtensionAccess,
            lentSignIns: lentSignIns,
            shell: shell,
            fetchesExchangeRates: fetchesExchangeRates,
            focusShortcut: focusShortcut,
            aiSourceByExtension: aiSourceByExtension
        )
        if let data = try? JSONEncoder().encode(stored) {
            write(data)
        }
    }
}

/// Export and import, in an extension so the class holds only the settings and how they are kept.
extension AppSettings {
    /// The stored settings, less any one whose value cannot be read: that one takes its default, the rest stay.
    private static func read(_ data: Data) -> Stored? {
        guard let salvaged = SettingsSalvage.decode(Stored.self, from: data) else { return nil }
        if !salvaged.dropped.isEmpty {
            Log.app.warning("Settings that could not be read took their defaults: \(salvaged.dropped.sorted().joined(separator: ", "))")
        }
        return salvaged.value
    }

    /// The settings as they are saved, for an export file.
    func exportedJSON() throws -> Data {
        save()
        return defaults.data(forKey: Self.defaultsKey) ?? Data("{}".utf8)
    }

    /// Replaces every setting with an exported copy and saves it.
    func importJSON(_ data: Data) throws {
        guard let stored = Self.read(data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        apply(stored)
        save()
    }
}

/// How often and how recently each root item was opened, for ranking. Kept apart from settings
/// because it changes on every launch.
final class UsageStore {
    static let shared = UsageStore()

    struct Record: Codable {
        var count: Int
        var lastUsed: Date
    }

    private(set) var records: [String: Record]
    /// The searches that ended in something being opened, oldest first, each once. Read from the defaults
    /// each time: the settings window is another process, and clears them there.
    var queries: [String] {
        defaults.stringArray(forKey: Self.queriesKey) ?? []
    }

    static let queryLimit = 50
    private static let defaultsKey = "usage"
    private static let queriesKey = "queries"
    /// How long a burst of uses is gathered before the map is written once.
    static let saveDelay: TimeInterval = 1
    private let defaults: UserDefaults
    private let now: () -> Date
    /// Runs a deferred save. `later` is injectable so a test can run the timer by hand.
    private let later: (TimeInterval, DispatchWorkItem) -> Void
    /// The save waiting for its timer. Nil once it has run or been flushed.
    private var pendingSave: DispatchWorkItem?

    /// `now` is injectable so ranking by recency can be tested against a fixed clock.
    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        later: @escaping (TimeInterval, DispatchWorkItem) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) }
    ) {
        self.defaults = defaults
        self.now = now
        self.later = later
        records = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    /// Remembers a search for the Up arrow to bring back. One typed again moves to the newest place.
    func recordQuery(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var queries = queries
        queries.removeAll { $0 == query }
        queries.append(query)
        queries.removeFirst(max(0, queries.count - Self.queryLimit))
        defaults.set(queries, forKey: Self.queriesKey)
    }

    func forgetQueries() {
        defaults.removeObject(forKey: Self.queriesKey)
    }

    /// Counts the use at once and writes it down later, in one save per burst: recording what was
    /// opened no longer encodes the whole map and carries it through the defaults server at the
    /// very moment the panel is giving way to an app. A burst restarts the timer, so uses keep joining it.
    func recordUse(of id: String) {
        var record = records[id] ?? Record(count: 0, lastUsed: .distantPast)
        record.count += 1
        record.lastUsed = now()
        records[id] = record
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        later(Self.saveDelay, work)
    }

    /// Writes what has not been saved yet: when the burst's timer runs out, and when the app quits.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func frecency(of id: String) -> Double {
        guard let record = records[id] else { return 0 }
        return Ranking.frecency(count: record.count, age: now().timeIntervalSince(record.lastUsed))
    }
}
