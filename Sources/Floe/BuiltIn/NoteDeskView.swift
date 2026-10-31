//
//  NoteDeskView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The notes of the notes app the user chose, a folder of them or Apple Notes: the list beside the note on screen,
/// shown as a document to read and write where it stands. The bottom says where the notes are kept.
struct NoteDeskView: View {
    @ObservedObject var desk: NoteDeskModel
    /// For the gear. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    let focusToken: Int
    /// Bumped to put the caret in the note.
    @State private var editorFocus = 0

    var body: some View {
        PanelSections {
            SearchBar(placeholder: String(localized: "Search notes, or name a new one…", bundle: .floe), text: $desk.query, focusToken: focusToken) { EmptyView() }
        } content: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .onChange(of: desk.isEditing) {
            if desk.isEditing {
                editorFocus += 1
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if case let .elsewhere(app) = desk.place {
            ThawEmptyState(
                systemImage: "note.text",
                title: app.isEmpty ? .floe("Choose a folder for your notes") : .floe("Your notes are kept in \(app)"),
                caption: .floe("To read and write notes here, choose Apple Notes or a folder of notes, such as an Obsidian vault, as the notes app in Settings.")
            )
        } else if let failure = desk.failure {
            ThawEmptyState(
                systemImage: "exclamationmark.triangle",
                title: .verbatim(failure),
                actionTitle: desk.needsAutomation ? .floe("Open Settings") : nil,
                action: desk.needsAutomation ? { desk.askForAutomation() } : nil
            )
        } else if desk.notes.isEmpty {
            NoteEmptyState(store: desk.store)
        } else if desk.filtered.isEmpty {
            ThawEmptyState(systemImage: "magnifyingglass", title: .floe("No note has that name"), caption: .floe("Press ⌘N to make one."))
        } else {
            HStack(spacing: 0) {
                list(desk.filtered)
                    .frame(width: 220)
                Divider()
                if let notice = desk.notice {
                    ThawEmptyState(systemImage: "doc.text", title: .verbatim(notice))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NoteDocument(
                        text: $desk.text,
                        store: desk.store,
                        isEditable: desk.selected != nil,
                        focusToken: editorFocus,
                        onFocusChange: { desk.editorFocusChanged($0) }
                    )
                }
            }
        }
    }

    private func list(_ notes: [FloatingNote]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        NoteListRow(note: note, selected: index == desk.selection)
                            .onTapGesture { desk.select(index) }
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .onChange(of: desk.selection) {
                if notes.indices.contains(desk.selection) {
                    proxy.scrollTo(notes[desk.selection].id)
                }
            }
        }
    }

    private var bottomBar: some View {
        PanelBottomBar {
            OpenSettingsButton(model: launcher)
            if desk.keepsNotes {
                NotePlace(store: desk.store)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if desk.keepsNotes {
                ShortcutHintButton(title: String(localized: "New Note", bundle: .floe)) { desk.makeNote() } hint: {
                    KeyCapView(text: "⌘")
                    KeyCapView(text: "N")
                }
            }
            if desk.selected != nil {
                ShortcutHintButton(title: openTitle) { desk.openInApp() } hint: {
                    KeyCapView(text: "⌘")
                    KeyCapView(text: "O")
                }
                // While writing, ⌘E is the editor's, for code: Escape is the way out.
                ShortcutHintButton(title: desk.isEditing ? String(localized: "Done", bundle: .floe, comment: "A button that ends writing a note.") : String(localized: "Write", bundle: .floe, comment: "A verb on a button: start changing the note on screen.")) { desk.toggleEditing() } hint: {
                    if desk.isEditing {
                        KeyCapView(text: "esc")
                    } else {
                        KeyCapView(text: "⌘")
                        KeyCapView(text: "E")
                    }
                }
            }
        }
    }

    private var openTitle: String {
        if let owner = desk.store.opener {
            return String(localized: "Open in \(owner)", bundle: .floe, comment: "A button. The placeholder is the name of an app.")
        }
        return String(localized: "Open", bundle: .floe, comment: "A verb on a button: open the selected result.")
    }
}
