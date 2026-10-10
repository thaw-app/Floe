//
//  QuicklinksSettingsPage.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import SwiftUI
import ThawUI

struct QuicklinksSettingsPage: View {
    @ObservedObject private var store: QuicklinkStore = .shared
    @State private var draft = Quicklink(name: "", keyword: "", url: "https://")
    @State private var editingID: UUID?
    @State private var showingEditor = false
    @State private var pendingDelete: Quicklink?
    @State private var editorError = ""

    init() {}

    var body: some View {
        Form {
            ThawSection(header: { Text("Quicklinks") }, content: {
                ForEach(store.links) { link in
                    HStack(spacing: ThawSpacing.row) {
                        QuicklinkTile(symbol: link.symbol)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.name)
                            Text(link.keyword)
                                .font(ThawType.footnote)
                                .foregroundStyle(.secondary)
                            Text(link.url)
                                .font(ThawType.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Edit") { edit(link) }
                    }
                }
                Button("New Quicklink") { add() }
            })
            ThawSection(
                header: { Text("Fallbacks") },
                content: {
                    let fallbacks = store.fallbacks
                    ForEach(fallbacks) { link in
                        HStack(spacing: ThawSpacing.row) {
                            QuicklinkTile(symbol: link.symbol)
                            Text(link.name)
                            Spacer()
                            Button { store.move(link, by: -1) } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(fallbacks.first?.id == link.id)
                            Button { store.move(link, by: 1) } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(fallbacks.last?.id == link.id)
                        }
                    }
                },
                footer: { Text("Shown under your results when you search.") }
            )
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingEditor) {
            editor
        }
        .alert("Delete this quicklink?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: {
                if !$0 {
                    pendingDelete = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                if let link = pendingDelete {
                    store.remove(link)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var editor: some View {
        Form {
            ThawSection {
                TextField("Name", text: $draft.name)
                TextField("Keyword", text: $draft.keyword)
                TextField("URL", text: $draft.url)
                TextField("Symbol", text: $draft.symbol, prompt: Text("SF Symbol name"))
                Toggle("Use as fallback", isOn: $draft.isFallback)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use {query} where the search text goes.")
                    if !editorError.isEmpty {
                        Text(editorError).foregroundStyle(.red)
                    }
                }
            }
            if editingID != nil {
                ThawSection {
                    Button("Delete Quicklink", role: .destructive) {
                        if let id = editingID,
                           let link = store.links.first(where: { $0.id == id })
                        {
                            showingEditor = false
                            pendingDelete = link
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showingEditor = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
        .frame(minWidth: 380, minHeight: 320)
        .padding()
    }

    private var isValid: Bool {
        validationError == nil
    }

    private var validationError: String? {
        let keyword = draft.keyword.trimmingCharacters(in: .whitespaces)
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Enter a name.", bundle: .floe)
        }
        if keyword.isEmpty {
            return String(localized: "Enter a keyword.", bundle: .floe)
        }
        if keyword.contains(where: \.isWhitespace) {
            return String(localized: "Keywords cannot contain spaces.", bundle: .floe)
        }
        if !store.isKeywordUnique(keyword, ignoring: editingID) {
            return String(localized: "That keyword is already used.", bundle: .floe)
        }
        guard let url = URL(string: draft.url), let scheme = url.scheme, !scheme.isEmpty else {
            return String(localized: "Enter a URL with a scheme, like https://.", bundle: .floe)
        }
        return nil
    }

    private func add() {
        draft = Quicklink(name: "", keyword: "", url: "https://")
        editingID = nil
        editorError = ""
        showingEditor = true
    }

    private func edit(_ link: Quicklink) {
        draft = link
        editingID = link.id
        editorError = ""
        showingEditor = true
    }

    private func save() {
        if let error = validationError {
            editorError = error
            return
        }
        draft.keyword = draft.keyword.trimmingCharacters(in: .whitespaces)
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        if editingID != nil {
            store.update(draft)
        } else {
            store.add(draft)
        }
        showingEditor = false
    }
}

private struct QuicklinkTile: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(
                colors: [Color.orange.mix(with: .white, by: 0.18), .orange],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
