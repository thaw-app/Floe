//
//  NoteDeskModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import AsyncAlgorithms

/// The notes view in the panel: the list, the note on screen and its text, read from and written to the folder.
final class NoteDeskModel: ObservableObject {
    enum Place: Equatable {
        case folder(URL, owner: String?)
        /// The notes app is one Floe can only send text to. With its name.
        case elsewhere(String)
    }

    @Published var query = "" {
        didSet { select(0) }
    }

    @Published private(set) var notes: [DeskNote] = []
    @Published private(set) var selection = 0
    /// The note on screen as the editor holds it.
    @Published var text = "" {
        didSet { scheduleSave() }
    }

    @Published var isEditing = false
    /// Why the note on screen has no text here, when it has none.
    @Published private(set) var notice: String?
    let place: Place
    var host = ModeHost()
    private let record: (Receipt) -> Void
    private let open: (URL) -> Void
    private let list: @Sendable (URL) -> [DeskNote]
    /// The note that was read: where, what, and when its file was last changed.
    private var loaded: (url: URL, text: String, modified: Date?)?
    /// Each edit, so a pause in typing saves once.
    private let edits = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private var saving: Task<Void, Never>?
    private var watch: Timer?
    /// Counts the listings started, so one that finishes after a newer one is dropped.
    private var listings = 0

    init(
        app: NotesApp,
        folder path: String,
        record: @escaping (Receipt) -> Void = { _ in
            // No receipts kept.
        },
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        list: @escaping @Sendable (URL) -> [DeskNote] = NoteDesk.notes
    ) {
        self.record = record
        self.open = open
        self.list = list
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isFolder: ObjCBool = false
        if app == .folder, !path.isEmpty, FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue {
            place = .folder(folder, owner: NoteDesk.owner(of: folder))
        } else {
            place = .elsewhere(app == .folder ? "" : app.title)
        }
        let edits = edits.stream
        saving = Task { @MainActor [weak self] in
            for await _ in edits.debounce(for: .milliseconds(800)) {
                self?.flush()
            }
        }
    }

    var folder: URL? {
        if case let .folder(folder, _) = place {
            return folder
        }
        return nil
    }

    var owner: String? {
        if case let .folder(_, owner) = place {
            return owner
        }
        return nil
    }

    var filtered: [DeskNote] {
        NoteDesk.matching(notes, query: query)
    }

    var selected: DeskNote? {
        let shown = filtered
        return shown.indices.contains(selection) ? shown[selection] : nil
    }

    // MARK: Reading

    /// Reads the folder off the main thread and shows its newest note. The task is for tests to wait on.
    @discardableResult
    func start(selecting chosen: URL? = nil) -> Task<Void, Never> {
        guard let folder else { return Task {} }
        if watch == nil {
            // The app that owns the folder may write the note on screen: a look at its date is all this costs.
            watch = Timer.scheduledOnMain(withTimeInterval: 1.5, repeats: true) { [weak self] in self?.reloadIfChanged() }
        }
        listings += 1
        let listing = listings
        return Task { [list] in
            let found = await Task.detached { list(folder) }.value
            guard listing == listings else { return }
            notes = found
            select(chosen.flatMap { url in filtered.firstIndex { $0.url == url } } ?? 0)
        }
    }

    func select(_ index: Int) {
        flush()
        let shown = filtered
        selection = max(0, min(index, shown.count - 1))
        show(shown.indices.contains(selection) ? shown[selection] : nil)
    }

    private func show(_ note: DeskNote?) {
        guard let note else {
            loaded = nil
            notice = nil
            text = ""
            return
        }
        guard let read = NoteDesk.read(note.url) else {
            loaded = nil
            text = ""
            notice = String(localized: "This note is too large to show here, or is not text.", bundle: .floe)
            return
        }
        notice = nil
        loaded = (note.url, read.text, read.modified)
        text = read.text
    }

    /// Takes what another app wrote into the note on screen, unless the editor holds changes of its own.
    func reloadIfChanged() {
        guard let loaded, text == loaded.text, let onDisk = NoteDesk.modified(loaded.url),
              onDisk != loaded.modified, let read = NoteDesk.read(loaded.url)
        else { return }
        self.loaded = (loaded.url, read.text, read.modified)
        text = read.text
    }

    // MARK: Writing

    private func scheduleSave() {
        guard let loaded, text != loaded.text else { return }
        edits.continuation.yield()
    }

    /// Writes the editor's text now, if it differs from what was read.
    /// A save the pause asks for after this one finds nothing new and writes nothing.
    func flush() {
        guard let loaded, text != loaded.text else { return }
        do {
            switch try NoteDesk.save(text, to: loaded.url, readAt: loaded.modified) {
            case let .written(modified):
                self.loaded = (loaded.url, text, modified)
            case let .keptBeside(copy):
                // The file is another app's now: the editor moves to its own copy and goes on.
                self.loaded = (copy, text, NoteDesk.modified(copy))
                host.showHUD(String(localized: "The note changed elsewhere. Yours is saved as \(copy.deletingPathExtension().lastPathComponent).", bundle: .floe, comment: "The placeholder is the name of a file."))
                start(selecting: copy)
            }
        } catch {
            host.showHUD(String(localized: "Couldn’t save the note: \(error.localizedDescription)", bundle: .floe, comment: "The placeholder is the reason the system gave."))
        }
    }

    /// A new note named by what is typed in the search, or by the time when nothing is. It opens for writing
    /// once the folder is read again, which is the task a test waits on.
    @discardableResult
    func makeNote(now: Date = Date()) -> Task<Void, Never> {
        guard let folder else { return Task {} }
        flush()
        do {
            let file = try NoteFiles.write(query.trimmingCharacters(in: .whitespacesAndNewlines), in: folder, now: now)
            record(.note(file, now: now))
            query = ""
            isEditing = true
            return start(selecting: file)
        } catch {
            host.showHUD(String(localized: "Couldn’t save the note: \(error.localizedDescription)", bundle: .floe, comment: "The placeholder is the reason the system gave."))
            return Task {}
        }
    }

    func openInApp() {
        flush()
        guard let note = loaded?.url ?? selected?.url else { return }
        host.dismiss()
        open(NoteDesk.link(to: note, owner: owner))
    }

    func toggleEditing() {
        guard loaded != nil else { return }
        isEditing.toggle()
        if !isEditing {
            flush()
            host.refocus()
        }
    }

    /// Leaving the view: nothing typed is lost, and the folder is no longer looked at.
    func close() {
        flush()
        saving?.cancel()
        saving = nil
        watch?.invalidate()
        watch = nil
    }

    // MARK: Keys

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
            host.close()
        case 53:
            query = ""
        default: return false
        }
        return true
    }

    /// Command with E, N or O.
    private func runCommand(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 14: toggleEditing()
        case 45: makeNote()
        case 31: openInApp()
        default: return false
        }
        return true
    }
}
