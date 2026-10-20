//
//  Model+Notes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The notes view: the notes of the notes app the user chose, read and written in the panel.
extension LauncherModel {
    func openNoteDesk() {
        runner.endOpenCommand()
        setup = nil
        isSearchingMenuBar = false
        menuItemSearch = nil
        isShowingClipboardHistory = false
        isSearchingFiles = false
        closeNoteDesk()
        let desk = NoteDeskModel(app: settings.notesApp, folder: settings.notesFolder) { [weak self] in self?.record($0) }
        desk.host = modeHost { [weak self] in
            self?.closeNoteDesk()
            self?.focusToken += 1
        }
        noteDesk = desk
        if let saving = noteDeskSave {
            // The desk closed last may still be writing a note this one is about to read.
            Task {
                _ = await saving.value
                desk.start()
            }
        } else {
            desk.start()
        }
        panelHost.showPanel()
        focusToken += 1
    }

    /// The floating note is a window of its own: the launcher goes, and the note stays over the app the user was in.
    func openFloatingNote() {
        panelHost.hidePanel()
        reset()
        panelHost.showFloatingNote()
    }

    /// Saves what is being written as the view goes. The save is kept, for the next desk and the end of the process to wait on.
    func closeNoteDesk() {
        if let noteDesk {
            noteDeskSave = noteDesk.close()
        }
        noteDesk = nil
    }
}
