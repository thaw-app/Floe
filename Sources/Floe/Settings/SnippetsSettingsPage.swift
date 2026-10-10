//
//  SnippetsSettingsPage.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Snippets: whether keywords expand as you type, and the list of snippets with their editor.
struct SnippetsSettingsPage: View {
    @ObservedObject private var store = SnippetStore.shared
    @State private var editing: Snippet?

    var body: some View {
        Form {
            ThawSection(
                header: { Text("Expansion") },
                content: { Toggle("Expand keywords as you type", isOn: $store.expansionEnabled) },
                footer: {
                    Text("Type a snippet's keyword in any app and Floe replaces it with the snippet. Needs Accessibility. Password fields are skipped.")
                }
            )
            ThawSection("Snippets") {
                if store.snippets.isEmpty {
                    Text("No snippets yet.").foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { snippet in
                    Button {
                        editing = snippet
                    } label: {
                        LabeledContent {
                            Text(snippet.keyword).font(.body.monospaced()).foregroundStyle(.secondary)
                        } label: {
                            Text(snippet.name)
                            Text(snippet.firstLine).lineLimit(1)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Button("New Snippet") { editing = Snippet(name: "", keyword: "", text: "") }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet, isNew: !store.snippets.contains { $0.id == snippet.id }) { result in
                if let result {
                    store.upsert(result)
                }
                editing = nil
            } onDelete: {
                store.remove(snippet)
                editing = nil
            }
        }
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    let isNew: Bool
    let onDone: (Snippet?) -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    private var problem: String? {
        Snippet.keywordProblem(snippet.keyword, id: snippet.id, among: SnippetStore.shared.snippets)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ThawSection {
                    TextField("Name", text: $snippet.name)
                    TextField("Keyword", text: $snippet.keyword, prompt: Text(";sig"))
                    if let problem, !snippet.keyword.isEmpty {
                        Text(problem).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Placeholders: {clipboard} {date} {time} {datetime} {uuid} {day}")
                }
                ThawSection("Text") {
                    TextEditor(text: $snippet.text)
                        .font(.body.monospaced())
                        .frame(minHeight: 140)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete…", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("Cancel") { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    snippet.keyword = snippet.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    onDone(snippet)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(snippet.name.trimmingCharacters(in: .whitespaces).isEmpty || problem != nil)
            }
            .padding()
        }
        .frame(width: 460, height: 440)
        .alert("Delete \u{201C}\(snippet.name)\u{201D}?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { /* the alert closes itself */ }
        }
    }
}
