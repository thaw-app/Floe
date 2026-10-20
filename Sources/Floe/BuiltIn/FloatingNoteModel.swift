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
    /// What of the note on screen is saved, and the saves that keep it so.
    private lazy var saver: NoteSaver = {
        let saver = NoteSaver(store: store) { [weak self] in self?.text }
        saver.didSave = { [weak self] stored, written in await self?.saved(stored, written: written) }
        saver.didFail = { [weak self] in self?.report($0, saving: true) }
        return saver
    }()

    /// Each edit, so a pause in typing saves once.
    private let edits = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private var pausing: Task<Void, Never>?
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

    var hasUnsavedText: Bool {
        saver.hasUnsavedText
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
            guard await commit() else { return }
            await load(other)
        }
    }

    private func load(_ other: FloatingNote) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let read = try await store.read(other)
            saver.show(read.note, text: read.text)
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
        guard let shown = saver.saved?.note, !hasUnsavedText, !isLoading else { return Task { /* Nothing to take: the editor's text comes first. */ } }
        return Task {
            guard let changed = await store.changes(to: shown),
                  saver.saved?.note.id == shown.id, !hasUnsavedText
            else { return }
            saver.show(changed.note, text: changed.text)
            note = changed.note
            text = changed.text
        }
    }

    // MARK: Writing

    private func scheduleSave() {
        guard hasUnsavedText else { return }
        edits.continuation.yield()
    }

    /// Writes the editor's text once the save before it is done, and again for what is typed meanwhile.
    /// Answers whether the note on screen is saved.
    @discardableResult
    func flush() -> Task<Bool, Never> {
        saver.flush()
    }

    /// Saves now and waits. True when nothing is left unsaved.
    func commit() async -> Bool {
        await saver.commit()
    }

    private func saved(_ stored: FloatingNote, written: FloatingNote) async {
        note = stored
        if stored.id == written.id {
            clearStatus()
        } else {
            // The file was another app's by then: the text went into a copy beside it, which is the note now.
            status = String(localized: "The note changed elsewhere. Yours is saved as \(stored.name).", bundle: .floe, comment: "The placeholder is the name of a file.")
            await refreshList()
        }
    }

    /// A new note, named by its first line once one is typed, or by the name given. The note on screen is saved first.
    @discardableResult
    func makeNote(named name: String = "") -> Task<Void, Never> {
        Task {
            guard listsNotes, await commit() else { return }
            do {
                let made = try await store.makeNote(named: name)
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

    /// The window's keys: ⌘W and Escape close, ⌘N makes a note, ⌘[ and ⌘] step through the notes as the Notes menu
    /// lists them. Everything else is the text's.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if flags == .command {
            return runCommand(event.keyCode)
        }
        guard flags.isEmpty, event.keyCode == 53 else { return false }
        requestClose()
        return true
    }

    /// Command with W, N, [ or ].
    private func runCommand(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 13: requestClose()
        case 45 where listsNotes: makeNote()
        case 33 where listsNotes: step(by: -1)
        case 30 where listsNotes: step(by: 1)
        default: return false
        }
        return true
    }

    /// Opens the note before or after the one on screen, in the order the Notes menu lists them.
    @discardableResult
    func step(by offset: Int) -> Task<Void, Never> {
        guard let next = notes.item(stepping: offset, from: { $0.id == note?.id }), next.id != note?.id else { return Task { /* No other note to step to. */ } }
        return open(next)
    }
}
