//
//  FloatingNoteModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import AsyncAlgorithms

/// The floating note: one note at a time from the store of the notes app, saved after a pause in typing,
/// on a switch and on close. A save that fails keeps the text on screen and says why.
final class FloatingNoteModel: ObservableObject {
    /// What the note asks of the world outside its store. Tests pass their own: nothing opens, no alert shows.
    struct Environment {
        /// Hands the scratch note's text to the notes app, then answers with what went wrong, or nil when it went.
        var send: (NoteAction, String, @escaping (String?) -> Void) -> Void = { _, _, done in done(nil) }
        var askForAutomation: () -> Void = { SystemCommand.askForAutomation(toControl: "Notes") }
        /// How long typing has to stop before the note is saved.
        var pause = Duration.milliseconds(800)
        /// How often the note on screen is checked for changes made elsewhere.
        var watchInterval: TimeInterval = 1.5
    }

    @Published private(set) var notes: [FloatingNote] = []
    /// The note on screen. Nil before the first is read, and when the store has none.
    @Published private(set) var note: FloatingNote?
    @Published var text = "" {
        didSet { scheduleSave() }
    }

    /// Whether the list of notes covers the editor, to pick another or name a new one.
    @Published var isSwitching = false {
        didSet {
            query = ""
            selection = 0
        }
    }

    @Published var query = "" {
        didSet { selection = 0 }
    }

    @Published var selection = 0
    /// While a note is read the editor waits, so nothing typed lands in the note that is going.
    @Published private(set) var isLoading = false
    /// What went wrong last, or what the store did that the user should know. Cleared by the next save that works.
    @Published private(set) var status: String?
    /// Whether that was macOS refusing Floe control of Notes, which a button can ask about again.
    @Published private(set) var needsAutomation = false

    let store: any FloatingNoteStore
    /// Closes the window, once the note is saved.
    var close: () -> Void = { /* no window */ }
    private let environment: Environment
    /// The note that was read or saved last, and its text then. The editor differs from it while there are edits to save.
    private var loaded: (note: FloatingNote, text: String)?
    /// Each edit, so a pause in typing saves once.
    private let edits = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private var pausing: Task<Void, Never>?
    /// The save in flight. Each new one waits for it, so two never write the same note at once.
    private var writing: Task<Bool, Never>?
    private var watch: Timer?

    init(store: any FloatingNoteStore, environment: Environment = Environment()) {
        self.store = store
        self.environment = environment
        let edits = edits.stream
        let pause = environment.pause
        pausing = Task { @MainActor [weak self] in
            for await _ in edits.debounce(for: pause) {
                self?.flush()
            }
        }
    }

    /// A note dropped without `stop()` still ends its saving task.
    deinit {
        edits.continuation.finish()
    }

    /// Whether there are notes to switch between and make. The scratch note is the only one of its kind.
    var listsNotes: Bool {
        store.sendsTo == nil
    }

    var filtered: [FloatingNote] {
        guard !query.isEmpty else { return notes }
        return notes.ranked { Fuzzy.score(query, $0.name) }
    }

    var hasUnsavedText: Bool {
        loaded.map { $0.text != text } ?? false
    }

    // MARK: Reading

    /// Lists the notes and opens the newest. The task is for tests to wait on.
    @discardableResult
    func start() -> Task<Void, Never> {
        if watch == nil, listsNotes {
            watch = Timer.scheduledOnMain(withTimeInterval: environment.watchInterval, repeats: true) { [weak self] in
                self?.reloadIfChanged()
            }
        }
        return Task {
            guard await refreshList() else { return }
            if let first = notes.first {
                await load(first)
            }
        }
    }

    /// Reads the list again. False when the store could not be reached, which the status then says.
    @discardableResult
    private func refreshList() async -> Bool {
        do {
            notes = try await store.notes()
            return true
        } catch {
            report(error, saving: false)
            return false
        }
    }

    /// Saves the note on screen, then shows another. A failed save keeps the note and its text on screen.
    @discardableResult
    func open(_ other: FloatingNote) -> Task<Void, Never> {
        Task {
            let saved = await commit()
            // Either way the list goes: on a failed save, to show the text it kept and the reason.
            isSwitching = false
            guard saved else { return }
            await load(other)
        }
    }

    private func load(_ other: FloatingNote) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let read = try await store.read(other)
            loaded = read
            note = read.note
            text = read.text
            clearStatus()
        } catch {
            report(error, saving: false)
        }
    }

    /// Takes what another app wrote into the note on screen, unless the editor holds changes of its own.
    @discardableResult
    func reloadIfChanged() -> Task<Void, Never> {
        guard let loaded, !hasUnsavedText, !isLoading else { return Task {} }
        return Task {
            guard let changed = await store.changes(to: loaded.note),
                  self.loaded?.note.id == loaded.note.id, !hasUnsavedText
            else { return }
            self.loaded = changed
            note = changed.note
            text = changed.text
        }
    }

    // MARK: Writing

    private func scheduleSave() {
        guard hasUnsavedText else { return }
        edits.continuation.yield()
    }

    /// Writes the editor's text once the save before it is done, if it differs from what was saved.
    /// Answers whether the note on screen is saved.
    @discardableResult
    func flush() -> Task<Bool, Never> {
        let before = writing
        let next = Task { [weak self] () -> Bool in
            _ = await before?.value
            return await self?.write() ?? false
        }
        writing = next
        return next
    }

    /// Saves now and waits. True when nothing is left unsaved.
    func commit() async -> Bool {
        await flush().value
    }

    private func write() async -> Bool {
        guard let loaded, text != loaded.text else { return true }
        let written = text
        do {
            let stored = try await store.save(written, to: loaded.note)
            self.loaded = (stored, written)
            note = stored
            if stored.id == loaded.note.id {
                clearStatus()
            } else {
                // The file was another app's by then: the text went into a copy beside it, which is the note now.
                status = String(localized: "The note changed elsewhere. Yours is saved as \(stored.name).", bundle: .floe, comment: "The placeholder is the name of a file.")
                await refreshList()
            }
            return true
        } catch {
            report(error, saving: true)
            return false
        }
    }

    /// A new note, named by what the list's search holds. The note on screen is saved first.
    @discardableResult
    func makeNote() -> Task<Void, Never> {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Task {
            guard listsNotes else { return }
            guard await commit() else {
                isSwitching = false
                return
            }
            do {
                let made = try await store.makeNote(named: name)
                isSwitching = false
                await refreshList()
                await load(made)
            } catch {
                report(error, saving: true)
            }
        }
    }

    // MARK: The scratch note

    /// Hands the scratch note to the notes app. What was sent is cleared once it went; what is typed meanwhile stays.
    func send(_ action: NoteAction = .new) {
        let sent = text
        guard store.sendsTo != nil, !sent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        environment.send(action, sent) { [weak self] failure in
            guard let self else { return }
            if let failure {
                status = failure
                return
            }
            if text == sent {
                text = ""
            }
            flush()
        }
    }

    // MARK: Closing

    /// Closes the window once the note is saved. When it cannot be, the window stays with the text and the reason.
    @discardableResult
    func requestClose() -> Task<Void, Never> {
        Task {
            guard await commit() else { return }
            stop()
            close()
        }
    }

    /// Ends the timers. The note's last save is the caller's to wait for.
    func stop() {
        edits.continuation.finish()
        pausing?.cancel()
        pausing = nil
        watch?.invalidate()
        watch = nil
    }

    func askForAutomation() {
        environment.askForAutomation()
    }

    private func report(_ error: Error, saving: Bool) {
        let known = error as? FloatingNoteError ?? .failed(error.localizedDescription)
        status = known.message(saving: saving)
        needsAutomation = known == .refused
    }

    private func clearStatus() {
        status = nil
        needsAutomation = false
    }

    // MARK: Keys

    /// The window's keys: ⌘W and Escape close, ⌘N makes a note, ⌘P shows the list. While the list is up the
    /// arrows and Return pick from it and Escape puts it away. Everything else is the text's.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if flags == .command {
            return runCommand(event.keyCode)
        }
        guard flags.isEmpty else { return false }
        if isSwitching {
            return handleListKey(event.keyCode)
        }
        guard event.keyCode == 53 else { return false }
        requestClose()
        return true
    }

    /// Command with W, N or P.
    private func runCommand(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 13: requestClose()
        case 45 where listsNotes: makeNote()
        case 35 where listsNotes: isSwitching.toggle()
        default: return false
        }
        return true
    }

    private func handleListKey(_ keyCode: UInt16) -> Bool {
        if let delta = Shortcuts.navigationDelta(keyCode) {
            selection = max(0, min(selection + delta, filtered.count - 1))
            return true
        }
        switch keyCode {
        case 36, 76:
            let shown = filtered
            if shown.indices.contains(selection) {
                open(shown[selection])
            }
        case 53: isSwitching = false
        default: return false
        }
        return true
    }
}
