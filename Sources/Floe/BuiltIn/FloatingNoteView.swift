//
//  FloatingNoteView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The floating note's window: the note's name on top, its text as plain text, and at the bottom where it is
/// kept, what went wrong, and for the scratch note the button that sends it.
struct FloatingNoteView: View {
    @ObservedObject var model: FloatingNoteModel
    @FocusState private var focus: Field?

    private enum Field {
        case text, search
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                editor
                if model.isSwitching {
                    switcher
                        .background(.background)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            bottomBar
        }
        .frame(minWidth: 280, minHeight: 200)
        .onChange(of: model.isSwitching) { focus = model.isSwitching ? .search : .text }
        .onAppear { focus = .text }
        // The editor waits while a note is read, so it takes the keyboard once the note is there.
        .onChange(of: model.note?.id) { focus = model.isSwitching ? .search : .text }
    }

    /// Clear of the window's buttons on the left, which sit in the same strip.
    private var header: some View {
        HStack(spacing: ThawSpacing.compact) {
            if model.listsNotes {
                Button {
                    model.isSwitching.toggle()
                } label: {
                    HStack(spacing: ThawSpacing.tight) {
                        Text(verbatim: title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(String(localized: "Switch Note (⌘P)", bundle: .floe, comment: "A tooltip on the note's name, which opens the list of notes."))
                Spacer(minLength: 0)
                Button {
                    model.makeNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help(String(localized: "New Note (⌘N)", bundle: .floe, comment: "A tooltip on the button that makes a new note."))
                .accessibilityLabel(String(localized: "New Note", bundle: .floe))
            } else {
                Text(verbatim: title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .font(ThawType.body.weight(.semibold))
        .padding(.leading, 76)
        .padding(.trailing, ThawSpacing.inset)
        .frame(height: 28)
    }

    private var title: String {
        model.note?.name ?? String(localized: "Floating Note", bundle: .floe, comment: "The command, and the window, that keep a note on top of other apps.")
    }

    @ViewBuilder
    private var editor: some View {
        if model.note == nil, !model.isLoading, model.listsNotes, model.status == nil {
            ThawEmptyState(
                systemImage: "note.text",
                title: .verbatim(String(localized: "No notes here yet", bundle: .floe)),
                caption: .verbatim(String(localized: "Press ⌘N to write the first.", bundle: .floe))
            )
        } else {
            TextEditor(text: $model.text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($focus, equals: .text)
                .disabled(model.note == nil || model.isLoading)
                .padding(ThawSpacing.row)
        }
    }

    private var switcher: some View {
        VStack(spacing: 0) {
            TextField(text: $model.query, prompt: Text(verbatim: String(localized: "Search notes, or name a new one…", bundle: .floe))) {
                Text(verbatim: String(localized: "Search notes", bundle: .floe, comment: "The label of the field that filters the list of notes."))
            }
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($focus, equals: .search)
            .padding(ThawSpacing.row)
            Divider()
            let shown = model.filtered
            if shown.isEmpty {
                ThawEmptyState(
                    systemImage: "magnifyingglass",
                    title: .verbatim(String(localized: "No note has that name", bundle: .floe)),
                    caption: .verbatim(String(localized: "Press ⌘N to make one.", bundle: .floe))
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, note in
                                row(note, selected: index == model.selection)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.open(note) }
                            }
                        }
                    }
                    .contentMargins(.all, ThawSpacing.tight, for: .scrollContent)
                    .onChange(of: model.selection) {
                        if shown.indices.contains(model.selection) {
                            proxy.scrollTo(shown[model.selection].id)
                        }
                    }
                }
            }
        }
    }

    private func row(_ note: FloatingNote, selected: Bool) -> some View {
        Text(verbatim: note.name.isEmpty ? " " : note.name)
            .font(ThawType.body)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(RowBackground(selected: selected))
            .id(note.id)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var bottomBar: some View {
        HStack(spacing: ThawSpacing.row) {
            if let status = model.status {
                Text(verbatim: status)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                if model.needsAutomation {
                    Button(String(localized: "Open Settings (System Settings)", defaultValue: "Open Settings", bundle: .floe, comment: "A button that opens System Settings.")) {
                        model.askForAutomation()
                    }
                }
            } else {
                Text(verbatim: model.store.place)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let recipient = model.store.sendsTo {
                if recipient.app.actions.contains(.append) {
                    Button(String(localized: "Append to Current Note", bundle: .floe)) { model.send(.append) }
                        .disabled(model.text.isEmpty)
                }
                Button(String(localized: "Send to \(recipient.name)", bundle: .floe, comment: "A button that hands the note to the notes app and clears it. The placeholder is the name of an app.")) {
                    model.send(.new)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.text.isEmpty)
            }
        }
        .font(ThawType.caption)
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.compact)
    }
}
