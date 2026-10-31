//
//  NoteViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// A note as a document, the way Glance and Lettera show one: the title large, the text set to read, no Markdown in
/// sight, and while it is written a bar of formatting buttons floating at the bottom.
struct NoteDocument: View {
    @Binding var text: String
    let store: any FloatingNoteStore
    var style = MarkdownEditorStyle.page
    var isEditable = true
    var focusToken = 0
    var onFocusChange: (Bool) -> Void = { _ in
        // Nobody asked.
    }

    @State private var commands = MarkdownEditorCommands()
    @State private var isWriting = false

    var body: some View {
        MarkdownEditor(
            text: $text,
            style: style,
            titleIsFirstLine: store is AppleNotesStore,
            isEditable: isEditable,
            focusToken: focusToken,
            commands: commands,
            onFocusChange: { focused in
                withThawAnimation(ThawMotion.quick) { isWriting = focused }
                onFocusChange(focused)
            }
        )
        .overlay(alignment: .bottom) {
            if isWriting, isEditable {
                MarkdownFormatBar(commands: commands)
                    .padding(.bottom, ThawSpacing.inset)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

/// The formatting buttons over a note being written: what the editor's keys do, for the pointer.
struct MarkdownFormatBar: View {
    let commands: MarkdownEditorCommands

    var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            Menu {
                Button(String(localized: "Heading 1", bundle: .floe)) { commands.run(.block(.heading(1))) }
                Button(String(localized: "Heading 2", bundle: .floe)) { commands.run(.block(.heading(2))) }
                Button(String(localized: "Heading 3", bundle: .floe)) { commands.run(.block(.heading(3))) }
                Button(String(localized: "Body Text", bundle: .floe)) { commands.run(.block(.body)) }
            } label: {
                Text(verbatim: "H")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Heading", bundle: .floe))
            button("checkmark.square", String(localized: "Task", bundle: .floe, comment: "A button that makes the line a task with a box to tick."), .block(.task))
            button("list.bullet", String(localized: "Bulleted List", bundle: .floe), .block(.bullet))
            button("list.number", String(localized: "Numbered List", bundle: .floe), .block(.numbered))
            Divider().frame(height: 16)
            button("bold", String(localized: "Bold", bundle: .floe), .bold)
            button("italic", String(localized: "Italic", bundle: .floe), .italic)
            button("chevron.left.forwardslash.chevron.right", String(localized: "Code", bundle: .floe), .code)
            button("link", String(localized: "Link", bundle: .floe), .link)
        }
        .padding(.horizontal, ThawSpacing.base)
        .padding(.vertical, ThawSpacing.tight)
        .thawGlass(.borderlessPanel, in: Capsule())
    }

    private func button(_ symbol: String, _ title: String, _ command: NoteTextView.Command) -> some View {
        Button {
            commands.run(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Where the notes are kept: the icon of the app that keeps them, or of their folder, and the place in words.
struct NotePlace: View {
    let store: any FloatingNoteStore

    var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            if let icon = store.placeIcon {
                AppIconView(path: icon, size: 14)
            } else {
                Image(systemName: "note.text")
            }
            Text(verbatim: store.place)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(store.place)
        .accessibilityElement(children: .combine)
    }
}

/// A note in a list: its name, and when it last changed where the store can say.
struct NoteListRow: View {
    let note: FloatingNote
    let selected: Bool

    var body: some View {
        HStack(spacing: ThawSpacing.base) {
            Text(verbatim: note.name.isEmpty ? " " : note.name)
                .lineLimit(1)
            Spacer(minLength: ThawSpacing.base)
            // Notes says no date through its scripts without a slow look at each note.
            if let modified = note.modified {
                Text(modified, format: .relative(presentation: .named))
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(ThawType.body)
        .modifier(RowBackground(selected: selected))
        .id(note.id)
        .accessibilityElement(children: .combine)
    }
}

/// What a store with no notes yet says, worded for where the notes are kept.
struct NoteEmptyState: View {
    let store: any FloatingNoteStore

    var body: some View {
        ThawEmptyState(
            systemImage: "note.text",
            title: .verbatim(store is AppleNotesStore
                ? String(localized: "No notes in Floe's folder in Notes yet", bundle: .floe)
                : String(localized: "No notes in this folder yet", bundle: .floe)),
            caption: .verbatim(String(localized: "Press ⌘N to write the first.", bundle: .floe))
        )
    }
}
