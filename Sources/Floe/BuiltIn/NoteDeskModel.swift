//
//  NoteDeskModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import AsyncAlgorithms

/// The notes view in the panel: the list, the note on screen and its text, read from and written back to where
/// the notes app keeps them, a folder of Markdown files or Floe's folder in Apple Notes.
final class NoteDeskModel: ObservableObject {
    enum Place: Equatable {
        case folder(URL, owner: String?)
        /// Floe's folder in Apple Notes.
        case appleNotes
        /// The notes app is one Floe can only send text to. With its name.
        case elsewhere(String)

        var folder: URL? {
            if case let .folder(folder, _) = self {
                return folder
            }
            return nil
        }
    }

    @Published var query = "" {
        didSet { select(0) }
    }

    @Published private(set) var notes: [FloatingNote] = []
    @Published private(set) var selection = 0
    /// The note on screen as the editor holds it.
    @Published var text = "" {
        didSet { scheduleSave() }
    }

    @Published var isEditing = false
    /// Why the note on screen has no text here, when it has none.
    @Published private(set) var notice: String?
    /// Why the notes could not be listed, when they could not.
    @Published private(set) var failure: String?
    /// Whether that was macOS refusing Floe control of Notes, which a button can ask about again.
    @Published private(set) var needsAutomation = false
    let place: Place
    let store: any FloatingNoteStore
    var host = ModeHost()
    /// The latest pick, save-and-open or new note. A test waits on it.
    private(set) var pending: Task<Void, Never>?
    /// What of the note on screen is saved, and the saves that keep it so.
    private lazy var saver: NoteSaver = {
        let saver = NoteSaver(store: store) { [weak self] in self?.text }
        saver.didSave = { [weak self] stored, written in self?.saved(stored, written: written) }
        saver.didFail = { [weak self] in self?.host.showHUD(Self.message($0, saving: true)) }
        return saver
    }()

    /// Each edit, so a pause in typing saves once.
    private let edits = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private var saving: Task<Void, Never>?
    private var watch: Timer?
    /// Counts the listings started, so one that finishes after a newer one is dropped.
    private var listings = 0
    /// Counts the picks, so a note read for one that was picked past is not shown.
    private var picks = 0

    /// The desk for the notes app the user chose. `open` and `list` reach a folder, `runScript` Apple Notes.
    convenience init(
        app: NotesApp,
        folder path: String,
        record: @escaping (Receipt) -> Void = { _ in
            // No receipts kept.
        },
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        list: @escaping @Sendable (URL) -> [DeskNote] = NoteDesk.notes,
        runScript: @escaping AppleScriptRunner = AppleScript.run
    ) {
        switch app {
        case .folder:
            let store = FolderNoteStore(folder: NoteDesk.folder(at: path), record: record, list: list, open: open)
            self.init(place: store.folder.map { .folder($0, owner: store.owner) } ?? .elsewhere(""), store: store)
        case .appleNotes:
            self.init(place: .appleNotes, store: AppleNotesStore(run: runScript))
        case .antinote, .custom:
            self.init(place: .elsewhere(app.title), store: FolderNoteStore(folder: nil))
        }
    }

    init(place: Place, store: any FloatingNoteStore) {
        self.place = place
        self.store = store
        let edits = edits.stream
        saving = Task { @MainActor [weak self] in
            for await _ in edits.debounce(for: .milliseconds(800)) {
                self?.flush()
            }
        }
    }

    /// A desk dropped without `close()` still ends its saving task.
    deinit {
        edits.continuation.finish()
    }

    var folder: URL? {
        place.folder
    }

    /// Whether the notes are read and written here, rather than only sent to their app.
    var keepsNotes: Bool {
        if case .elsewhere = place {
            return false
        }
        return true
    }

    var filtered: [FloatingNote] {
        guard !query.isEmpty else { return notes }
        return notes.ranked { Fuzzy.score(query, $0.name) }
    }

    var selected: FloatingNote? {
        let shown = filtered
        return shown.indices.contains(selection) ? shown[selection] : nil
    }

    // MARK: Reading

    /// Lists the notes off the main thread and shows the newest, or the one with the id chosen. The task is for
    /// tests to wait on.
    @discardableResult
    func start(selecting chosen: String? = nil) -> Task<Void, Never> {
        guard keepsNotes else { return Task { /* No notes to list: they go to their app. */ } }
        if watch == nil, folder != nil {
            // The app that owns the folder may write the note on screen: a look at its date is all this costs.
            watch = Timer.scheduledOnMain(withTimeInterval: 1.5, repeats: true) { [weak self] in self?.reloadIfChanged() }
        }
        listings += 1
        let listing = listings
        return Task {
            let found: [FloatingNote]
            do {
                found = try await store.notes()
            } catch {
                guard listing == listings else { return }
                let known = error as? FloatingNoteError ?? .failed(error.localizedDescription)
                failure = known.message(saving: false)
                needsAutomation = known == .refused
                return
            }
            guard listing == listings else { return }
            failure = nil
            needsAutomation = false
            notes = found
            await select(chosen.flatMap(index(of:)) ?? 0).value
        }
    }

    private func index(of id: String) -> Int? {
        filtered.firstIndex { $0.id == id }
    }

    /// Moves the list to a note and shows it once the note on screen is saved. When that save fails, the note
    /// and its text stay on screen and the list goes back to it.
    @discardableResult
    func select(_ index: Int) -> Task<Void, Never> {
        let shown = filtered
        selection = max(0, min(index, shown.count - 1))
        let wanted = shown.indices.contains(selection) ? shown[selection] : nil
        picks += 1
        let pick = picks
        return run {
            var read: Result<(note: FloatingNote, text: String), Error>?
            // Typing while the next note was read leaves more to save: it is saved before that note shows.
            repeat {
                guard await self.saver.commit() else {
                    if pick == self.picks {
                        self.selection = self.filtered.firstIndex { $0.id == self.saver.saved?.note.id } ?? self.selection
                    }
                    return
                }
                read = await self.read(wanted)
                guard pick == self.picks else { return }
            } while self.saver.hasUnsavedText
            self.show(read)
        }
    }

    private func read(_ note: FloatingNote?) async -> Result<(note: FloatingNote, text: String), Error>? {
        guard let note else { return nil }
        do {
            return try await .success(store.read(note))
        } catch {
            return .failure(error)
        }
    }

    private func show(_ read: Result<(note: FloatingNote, text: String), Error>?) {
        switch read {
        case nil:
            saver.show(nil)
            notice = nil
            text = ""
        case let .success(read):
            saver.show(read.note, text: read.text)
            notice = nil
            text = read.text
        case let .failure(error):
            saver.show(nil)
            text = ""
            notice = Self.message(error, saving: false)
        }
    }

    /// Takes what another app wrote into the note on screen, unless the editor holds changes of its own.
    @discardableResult
    func reloadIfChanged() -> Task<Void, Never> {
        guard let shown = saver.saved?.note, !saver.hasUnsavedText else { return Task { /* Nothing to take: the editor's text comes first. */ } }
        return Task {
            guard let changed = await store.changes(to: shown), saver.saved?.note == shown, !saver.hasUnsavedText else { return }
            saver.show(changed.note, text: changed.text)
            text = changed.text
        }
    }

    // MARK: Writing

    private func scheduleSave() {
        guard saver.hasUnsavedText else { return }
        edits.continuation.yield()
    }

    /// Writes the editor's text once the save before it is done, and again for what is typed meanwhile.
    /// Answers whether the note on screen is saved.
    @discardableResult
    func flush() -> Task<Bool, Never> {
        saver.flush()
    }

    private func saved(_ stored: FloatingNote, written: FloatingNote) {
        guard stored.id != written.id else {
            // Notes names a note by its first line: the list follows what was typed.
            if let index = notes.firstIndex(where: { $0.id == stored.id }), notes[index].name != stored.name {
                notes[index].name = stored.name
            }
            return
        }
        // The file is another app's now: the editor moves to its own copy and goes on.
        host.showHUD(String(localized: "The note changed elsewhere. Yours is saved as \(stored.name).", bundle: .floe, comment: "The placeholder is the name of a file."))
        start(selecting: stored.id)
    }

    private static func message(_ error: Error, saving: Bool) -> String {
        (error as? FloatingNoteError ?? .failed(error.localizedDescription)).message(saving: saving)
    }

    /// A new note named by what is typed in the search, or by the time when nothing is. It opens for writing
    /// once the note on screen is saved and the notes are listed again.
    @discardableResult
    func makeNote() -> Task<Void, Never> {
        guard keepsNotes else { return Task { /* The notes app makes its own notes. */ } }
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return run {
            guard await self.saver.commit() else { return }
            do {
                let made = try await self.store.makeNote(named: name)
                self.query = ""
                self.isEditing = true
                await self.start(selecting: made.id).value
            } catch {
                self.host.showHUD(Self.message(error, saving: true))
            }
        }
    }

    /// Opens the note in the app that keeps it, once it is saved.
    @discardableResult
    func openInApp() -> Task<Void, Never> {
        run {
            guard await self.saver.commit(), let note = self.saver.saved?.note ?? self.selected else { return }
            do {
                try await self.store.open(note)
                self.host.dismiss()
            } catch {
                self.host.showHUD(Self.message(error, saving: false))
            }
        }
    }

    func toggleEditing() {
        guard saver.saved != nil else { return }
        isEditing.toggle()
        if !isEditing {
            flush()
            host.refocus()
        }
    }

    /// Leaves the view once the note is saved. When it cannot be, the view stays with the text, and the reason shows.
    @discardableResult
    func requestClose() -> Task<Void, Never> {
        run {
            guard await self.saver.commit() else { return }
            self.host.close()
        }
    }

    /// The view is gone: the notes are no longer looked at, and the task saves what was typed and answers whether it could.
    /// It keeps the desk until then.
    @discardableResult
    func close() -> Task<Bool, Never> {
        edits.continuation.finish()
        saving?.cancel()
        saving = nil
        watch?.invalidate()
        watch = nil
        return Task { await saver.commit() }
    }

    private func run(_ work: @escaping () async -> Void) -> Task<Void, Never> {
        let task = Task { await work() }
        pending = task
        return task
    }
}

// MARK: The editor

extension NoteDeskModel {
    /// The editor took the caret or let it go. Letting it go saves what was written.
    func editorFocusChanged(_ isFocused: Bool) {
        guard isEditing != isFocused else { return }
        isEditing = isFocused
        if !isFocused {
            flush()
        }
    }

    func askForAutomation() {
        SystemCommand.askForAutomation(toControl: "Notes")
    }
}

// MARK: Keys

extension NoteDeskModel {
    /// The panel's keys while the notes are on screen. While a note is edited, only the commands are taken:
    /// everything else is the text's.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if flags == .command {
            return runCommand(event.keyCode)
        }
        if isEditing {
            guard event.keyCode == 53 else { return false }
            toggleEditing()
            return true
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            select(selection + delta)
            return true
        }
        switch event.keyCode {
        case 36, 76:
            toggleEditing()
        case 53 where query.isEmpty:
            requestClose()
        case 53:
            query = ""
        default: return false
        }
        return true
    }

    /// Command with E, N or O.
    private func runCommand(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        // While writing, ⌘E is the editor's, for code.
        case 14 where !isEditing: toggleEditing()
        case 45: makeNote()
        case 31: openInApp()
        default: return false
        }
        return true
    }
}
