//
//  ClipboardHistoryView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import SwiftUI
import ThawUI

/// Saved copies: a searchable list with Pinned and day sections, and a preview
/// with metadata. Return pastes (Command-V when Accessibility allows it),
/// Escape goes back to the root search.
struct ClipboardHistoryView: View {
    @ObservedObject var clipboard: ClipboardHistoryModel
    /// For the gear. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    let focusToken: Int
    @ObservedObject var history: ClipboardHistoryStore
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        PanelSections {
            SearchBar(placeholder: String(localized: "Search clipboard history…", bundle: .floe), text: $clipboard.query, focusToken: focusToken) { EmptyView() }
        } content: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !settings.clipboardHistoryEnabled {
            ThawEmptyState(
                systemImage: "doc.on.clipboard",
                title: "Clipboard history is off",
                caption: "Choose Floe for Clipboard in Settings → Applications to keep copies here."
            )
        } else {
            let entries = clipboard.filteredEntries()
            if history.entries.isEmpty {
                ThawEmptyState(
                    systemImage: "doc.on.clipboard",
                    title: "Nothing copied yet",
                    caption: "Copies you make show up here."
                )
            } else if entries.isEmpty {
                ThawEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No copies match",
                    caption: "Try part of the copied text, link or app name."
                )
            } else {
                HStack(spacing: 0) {
                    list(entries: entries)
                    Divider()
                    preview
                        .frame(width: 250)
                }
            }
        }
    }

    private func list(entries: [ClipboardEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let (rest, pinned) = entries.partitioned(by: \.pinned)
                    let positions = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
                    if !pinned.isEmpty {
                        SearchSectionHeader(title: String(localized: "Pinned", bundle: .floe, comment: "The heading over the copies the user pinned."))
                        ForEach(pinned) { entry in row(entry, index: positions[entry.id] ?? 0) }
                    }
                    ForEach(Self.dayGroups(rest), id: \.title) { group in
                        SearchSectionHeader(title: group.title)
                        ForEach(group.entries) { entry in row(entry, index: positions[entry.id] ?? 0) }
                    }
                }
            }
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .onChange(of: history.entries.map(\.id)) { clipboard.entriesChanged() }
            .onChange(of: clipboard.selection) {
                if entries.indices.contains(clipboard.selection) {
                    proxy.scrollTo(entries[clipboard.selection].id)
                }
            }
        }
    }

    private func row(_ entry: ClipboardEntry, index: Int) -> some View {
        ClipboardRow(
            entry: entry,
            title: entry.title.isEmpty ? kindName(for: entry.kind) : entry.title,
            subtitle: rowSubtitle(for: entry),
            selected: index == clipboard.selection,
            clipboard: clipboard
        )
        .id(entry.id)
        .onTapGesture(count: 2) { clipboard.paste(entry) }
        .onTapGesture { clipboard.selection = index }
    }

    @ViewBuilder
    private var preview: some View {
        if let entry = clipboard.selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if entry.kind == .image, let image = history.image(for: entry) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                    } else if let text = entry.text {
                        Text(text)
                            .textSelection(.enabled)
                            .font(.system(size: 12))
                    }
                    if entry.kind == .file {
                        ForEach(entry.filePaths ?? [], id: \.self) { path in
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                    Divider()
                    metadata(title: "Kind", value: kindName(for: entry.kind))
                    metadata(title: "Copied", value: Self.dateFormatter.string(from: entry.date))
                    if let app = entry.sourceApp {
                        metadata(title: "App", value: app)
                    }
                    metadata(title: "Detail", value: detail(for: entry))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ThawEmptyState(systemImage: "doc.on.clipboard", title: "Select a copy to preview it")
        }
    }

    private func metadata(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12)).textSelection(.enabled)
        }
    }

    private func bottomBar() -> some View {
        HStack(spacing: ThawSpacing.row) {
            OpenSettingsButton(model: launcher)
            Spacer(minLength: 0)
            if let entry = clipboard.selectedEntry {
                ShortcutHintButton(title: ClipboardRow.pinTitle(for: entry)) { clipboard.togglePin(entry) } hint: {
                    KeyCapView(systemImage: "pin")
                }
                ShortcutHintButton(title: ClipboardRow.deleteTitle) { clipboard.delete(entry) } hint: {
                    KeyCapView(text: "⌫")
                }
                ShortcutHintButton(title: String(localized: "Copy", bundle: .floe, comment: "A button that copies the selected entry.")) { clipboard.copy(entry) } hint: {
                    KeyCapView(text: "⌘C")
                }
                ShortcutHintButton(title: String(localized: "Paste", bundle: .floe, comment: "A button that pastes the selected entry.")) { clipboard.paste(entry) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
    }

    private func kindName(for kind: ClipboardEntry.Kind) -> String {
        switch kind {
        case .text: String(localized: "Text", bundle: .floe, comment: "A kind of copied thing.")
        case .link: String(localized: "Link", bundle: .floe, comment: "A kind of copied thing.")
        case .image: String(localized: "Image", bundle: .floe, comment: "A copied picture.")
        case .file: String(localized: "File", bundle: .floe, comment: "A kind of copied thing.")
        }
    }

    private func rowSubtitle(for entry: ClipboardEntry) -> String {
        var parts: [String] = [Self.timeFormatter.string(from: entry.date)]
        if let app = entry.sourceApp {
            parts.append(app)
        }
        if entry.kind == .link, let text = entry.text, let host = URL(string: text)?.host {
            parts.append(host)
        }
        return parts.joined(separator: " · ")
    }

    private func detail(for entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text, .link:
            let count = (entry.text ?? "").count
            return String(localized: "\(count) characters", bundle: .floe, comment: "How long a copied text is.")
        case .file:
            let count = entry.filePaths?.count ?? 0
            return String(localized: "\(count) files", bundle: .floe, comment: "How many files were copied together.")
        case .image:
            if let name = entry.imageFile,
               let size = try? FileManager.default.attributesOfItem(atPath: ClipboardHistoryStore.directory.appendingPathComponent(name).path)[.size] as? Int
            {
                return Self.byteFormatter.string(fromByteCount: Int64(size))
            }
            return String(localized: "Image", bundle: .floe, comment: "A copied picture.")
        }
    }

    struct DayGroup {
        let title: String
        let entries: [ClipboardEntry]
    }

    static func dayGroups(_ entries: [ClipboardEntry], calendar: Calendar = .current) -> [DayGroup] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { day, entries in
                let title = if calendar.isDateInToday(day) {
                    String(localized: "Today", bundle: .floe, comment: "The heading over what was copied today.")
                } else if calendar.isDateInYesterday(day) {
                    String(localized: "Yesterday", bundle: .floe, comment: "The heading over what was copied yesterday.")
                } else {
                    dateFormatter.string(from: day)
                }
                return DayGroup(title: title, entries: entries)
            }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

/// One copy. While the pointer is over it, Pin and Delete buttons take the place of its pin mark.
private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let title: String
    let subtitle: String
    let selected: Bool
    let clipboard: ClipboardHistoryModel
    @State private var isHovering = false

    static func pinTitle(for entry: ClipboardEntry) -> String {
        entry.pinned
            ? String(localized: "Unpin", bundle: .floe, comment: "A button that takes a copy off the pinned list.")
            : String(localized: "Pin", bundle: .floe, comment: "A button that keeps a copy at the top of the list.")
    }

    static let deleteTitle = String(localized: "Delete", bundle: .floe, comment: "A button that removes a copy from the history.")

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(subtitle)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isHovering {
                button(Self.pinTitle(for: entry), symbol: entry.pinned ? "pin.slash" : "pin") { clipboard.togglePin(entry) }
                button(Self.deleteTitle, symbol: "trash") { clipboard.delete(entry) }
            } else if entry.pinned {
                Image(systemName: "pin.fill").font(ThawType.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .font(ThawType.body)
        .modifier(RowBackground(selected: selected))
        .modifier(PointerHover(isHovering: $isHovering))
        .accessibilityAction(named: Self.pinTitle(for: entry)) { clipboard.togglePin(entry) }
        .accessibilityAction(named: Self.deleteTitle) { clipboard.delete(entry) }
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
