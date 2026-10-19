//
//  NoteRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Notes typed in the search, handed to the app the user chose, and the floating note.
final class NoteRows {
    var host = RowHost()
    /// Opens the floating note's window.
    var openFloatingNote: () -> Void = { /* set by LauncherFeatures */ }
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func write(_ action: NoteAction, text: String) {
        Notes.perform(action, text: text, app: settings.notesApp, template: settings.notesURLTemplate, folder: settings.notesFolder, record: host.record) { [weak self] message in
            if let message {
                self?.host.showHUD(message)
            }
        }
    }
}

extension NoteRows: RowOwner {
    func returnTitle(for _: RootItem) -> String? {
        nil
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case .floatingNote:
            openFloatingNote()
        case let .note(action, text):
            host.leave()
            write(action, text: text)
        default:
            return false
        }
        return true
    }
}
