//
//  FileSearchView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import ThawUI

/// The file search: a query field above a list of files beside a preview of
/// the selected file, and the file's actions below.
struct FileSearchView: View {
    @ObservedObject var search: FileSearchModel
    @ObservedObject var spotlight: FileSearch
    /// For the gear and the Actions menu. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    let focusToken: Int

    var body: some View {
        PanelSections {
            SearchBar(placeholder: String(localized: "Search files…", bundle: .floe), text: $search.query, focusToken: focusToken, isLoading: spotlight.isSearching) { EmptyView() }
        } content: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
    }

    /// Either the matching files or the state that explains why there are none.
    @ViewBuilder
    private var content: some View {
        let results = spotlight.results
        if spotlight.isSearching, results.isEmpty {
            ThawEmptyState(systemImage: "doc", title: "Searching files…", isLoading: true)
        } else if results.isEmpty, search.query.isEmpty {
            ThawEmptyState(
                systemImage: "doc",
                title: "No recent files",
                caption: "Files you open will show up here."
            )
        } else if results.isEmpty {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No files match",
                caption: "Try part of a file's name."
            )
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, file in
                                FileSearchRow(file: file, selected: index == search.selection)
                                    .id(file.id)
                                    .onTapGesture(count: 2) { search.openSelectedFile() }
                                    .onTapGesture { search.selection = index }
                            }
                        }
                    }
                    .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
                    .onChange(of: search.selection) {
                        if results.indices.contains(search.selection) {
                            proxy.scrollTo(results[search.selection].id)
                        }
                    }
                }
                Divider()
                if let file = search.selectedFile {
                    FilePreview(file: file)
                        .frame(width: 250)
                } else {
                    Color.clear.frame(width: 250)
                }
            }
        }
    }

    private var bottomBar: some View {
        PanelBottomBar {
            OpenSettingsButton(model: launcher)

            Spacer(minLength: 0)

            ShortcutHintButton(title: String(localized: "Open", bundle: .floe, comment: "A button that opens the selected file.")) { search.openSelectedFile() } hint: {
                KeyCapView(systemImage: "return")
            }
            ShortcutHintButton(title: String(localized: "Show in Finder", bundle: .floe)) { search.revealSelectedFile() } hint: {
                KeyCapView(text: "⌘")
                KeyCapView(systemImage: "return")
            }
            // Copy Path keeps its shortcut and moves into the menu, with the rest of what a file can do.
            ActionsButton(model: launcher) { $0.fileSearch.selectedFile.map($0.fileSearch.actions) ?? [] }
        }
    }
}

struct FileSearchRow: View {
    let file: FileResult
    let selected: Bool

    private var parentName: String {
        file.url.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        PaletteRow(title: file.name, subtitle: nil, selected: selected, matched: file.matched) {
            AppIconView(path: file.url.path, size: 24)
        } trailing: {
            Text(parentName)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(parentName)")
    }
}

struct FilePreview: View {
    let file: FileResult

    private var values: URLResourceValues {
        let keys: Set<URLResourceKey> = [.localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey, .contentModificationDateKey]
        return (try? file.url.resourceValues(forKeys: keys)) ?? URLResourceValues()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileThumbnail(url: file.url, maxHeight: 180)
            Text(file.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                if let kind = values.localizedTypeDescription {
                    FileMetaRow(label: "Kind") { Text(kind).lineLimit(1) }
                }
                if values.isDirectory != true, let size = values.fileSize {
                    FileMetaRow(label: "Size") {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                }
                if let modified = values.contentModificationDate {
                    FileMetaRow(label: "Modified") {
                        Text(modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let lastUsed = file.lastUsed {
                    FileMetaRow(label: "Last opened") {
                        Text(lastUsed.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                FileMetaRow(label: "Where") {
                    Text(file.displayPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text("↵ Open").foregroundStyle(.secondary)
                Text("⌘Y Quick Look").foregroundStyle(.secondary)
                Text("⌘⇧C Copy Path").foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
        }
        .padding(ThawSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FileMetaRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            content.font(.system(size: 12))
        }
    }
}

/// A file's Quick Look thumbnail, or its Finder icon while that loads. Clicking it, or ⌘Y anywhere in the
/// preview, opens the full Quick Look panel.
struct FileThumbnail: View {
    let url: URL
    var maxHeight: CGFloat = 180
    @State private var thumbnail: NSImage?
    @State private var quickLook: URL?

    var body: some View {
        Button { quickLook = url } label: {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                } else {
                    AppIconView(path: url.path, size: 96)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .center)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("y", modifiers: .command)
        .help("Quick Look  ⌘Y")
        .accessibilityLabel("Quick Look \(url.lastPathComponent)")
        .quickLookPreview($quickLook)
        .task(id: url) { await load() }
    }

    private func load() async {
        thumbnail = nil
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 512, height: 512),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = representation.nsImage
        }
    }
}
