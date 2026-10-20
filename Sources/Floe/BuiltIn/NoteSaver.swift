//
//  NoteSaver.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// How much of the note on screen the store holds, for both note editors. Saves run one at a time, and one answers
/// yes only once the store holds the editor's text as it is now, including what was typed while it wrote.
final class NoteSaver {
    /// The note as it was read or saved last, and its text then. The editor differs from it while there are edits to save.
    private(set) var saved: (note: FloatingNote, text: String)?
    let store: any FloatingNoteStore
    /// After each write, the note as it stands and the one that was written to. They differ when the store
    /// kept the text beside a note that changed elsewhere.
    var didSave: (_ stored: FloatingNote, _ written: FloatingNote) async -> Void = { _, _ in
        // Nothing to tell.
    }

    var didFail: (Error) -> Void = { _ in
        // Nothing to tell.
    }

    /// The editor's text now. Nil once the editor is gone, which ends the saving.
    private let current: () -> String?
    /// The save in flight. Each new one waits for it, so two never write the same note at once.
    private var writing: Task<Bool, Never>?

    init(store: any FloatingNoteStore, current: @escaping () -> String?) {
        self.store = store
        self.current = current
    }

    var hasUnsavedText: Bool {
        saved.map { $0.text != current() } ?? false
    }

    /// The note just read: from now on the editor's text is measured against it. Nil when none is on screen.
    func show(_ note: FloatingNote?, text: String = "") {
        saved = note.map { ($0, text) }
    }

    /// Writes once the save before it is done. True when nothing is left unsaved, false when a write failed.
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
        // The text is read again after each write: an edit made while it ran is written before the answer.
        while let saved, let text = current(), text != saved.text {
            do {
                let stored = try await store.save(text, to: saved.note)
                self.saved = (stored, text)
                await didSave(stored, saved.note)
            } catch {
                didFail(error)
                return false
            }
        }
        return true
    }
}
