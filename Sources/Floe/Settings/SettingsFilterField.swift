//
//  SettingsFilterField.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// A page's own search: a filled field as wide as the page, so it reads apart from the settings search at
/// the top of the sidebar. Escape and the clear button empty it.
struct SettingsFilterField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, ThawSpacing.inset)
        .frame(height: 36)
        .background(.quaternary.opacity(0.6), in: Self.shape)
        // A click anywhere on the field, the glass included, puts the cursor in it.
        .contentShape(Self.shape)
        .onTapGesture { isFocused = true }
    }

    private static let shape = RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
}

/// What a page's filter shows when nothing matches, in the empty state the rest of Settings uses.
struct NoMatchesState: View {
    let query: String

    var body: some View {
        ThawEmptyState(
            systemImage: "magnifyingglass",
            title: "No results for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”",
            caption: "Check the spelling or try a shorter term."
        )
    }
}
