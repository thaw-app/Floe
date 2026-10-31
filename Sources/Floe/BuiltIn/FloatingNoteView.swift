//
//  FloatingNoteView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The floating note's window, laid out as a document window: the name, where it is kept and the notes menu in the
/// title bar, the note below. The bottom shows only for an error, or the scratch note's Send button.
struct FloatingNoteView: View {
    @ObservedObject var model: FloatingNoteModel
    /// The window's title bar, which the note's name and buttons share with the close button.
    var titleBarHeight: CGFloat = 40
    /// Bumped to put the caret in the note.
    @State private var editorFocus = 0

    var body: some View {
        VStack(spacing: 0) {
            titleBar
                .frame(height: titleBarHeight)
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.status != nil || model.store.sendsTo != nil {
                bottomBar
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 300, minHeight: 220)
        .onAppear { editorFocus += 1 }
        // The editor waits while a note is read, so it takes the keyboard once the note is there.
        .onChange(of: model.note?.id) { editorFocus += 1 }
    }

    /// In the window's title bar, beside its close button and centred on it.
    private var titleBar: some View {
        HStack(spacing: 10) {
            if model.listsNotes {
                notesMenu
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(ThawType.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                NotePlace(store: model.store)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.listsNotes {
                Button {
                    model.makeNote()
                } label: {
                    roundButton("square.and.pencil")
                }
                .buttonStyle(.plain)
                .help(String(localized: "New Note (⌘N)", bundle: .floe, comment: "A tooltip on the button that makes a new note."))
                .accessibilityLabel(String(localized: "New Note", bundle: .floe))
            }
        }
        // The close button ends 26 points in.
        .padding(.leading, 36)
        .padding(.trailing, 10)
    }

    /// The other notes, newest first, with the one on screen ticked. ⌘[ and ⌘] step through them too.
    private var notesMenu: some View {
        Menu {
            ForEach(model.notes) { note in
                Button {
                    model.open(note)
                } label: {
                    if note.id == model.note?.id {
                        Label(note.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: note.name)
                    }
                }
            }
            Divider()
            Button(String(localized: "New Note", bundle: .floe)) { model.makeNote() }
        } label: {
            roundButton("sidebar.left")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Notes", bundle: .floe))
        .accessibilityLabel(String(localized: "Notes", bundle: .floe))
    }

    private func roundButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(ThawType.symbol)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .thawGlass(.control, in: Circle())
            .contentShape(Circle())
    }

    private var title: String {
        model.note?.name ?? String(localized: "Floating Note", bundle: .floe, comment: "The command, and the window, that keep a note on top of other apps.")
    }

    @ViewBuilder
    private var editor: some View {
        if model.note == nil, !model.isLoading, model.listsNotes, model.status == nil {
            NoteEmptyState(store: model.store)
        } else {
            NoteDocument(
                text: $model.text,
                store: model.store,
                style: .compact,
                isEditable: model.note != nil && !model.isLoading,
                focusToken: editorFocus
            )
        }
    }

    private var bottomBar: some View {
        PanelBottomBar {
            if let status = model.status {
                Text(verbatim: status)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                if model.needsAutomation {
                    Button(String(localized: "Open Settings (System Settings)", defaultValue: "Open Settings", bundle: .floe, comment: "A button that opens System Settings.")) {
                        model.askForAutomation()
                    }
                }
            }
            Spacer(minLength: 0)
            if let recipient = model.store.sendsTo {
                if recipient.app.actions.contains(.append) {
                    Button(String(localized: "Append to Current Note", bundle: .floe)) { model.send(.append) }
                        .disabled(model.text.isEmpty)
                }
                ShortcutHintButton(title: String(localized: "Send to \(recipient.name)", bundle: .floe, comment: "A button that hands the note to the notes app and clears it. The placeholder is the name of an app.")) {
                    model.send(.new)
                } hint: {
                    KeyCapView(text: "⌘")
                    KeyCapView(systemImage: "return")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.text.isEmpty)
            }
        }
        .font(ThawType.caption)
    }
}
