//
//  ExtensionStoreSettingsPage.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

struct ExtensionStoreSettingsPage: View {
    @ObservedObject var store: ExtensionStore
    let settings: AppSettings
    @State private var query = ""
    /// The catalog against the query, as it was last worked out. The ranking runs when one of the two
    /// changes, not on every pass of the view, where a row's own state would ask for it again.
    @State private var matched: [StoreListing] = []
    @State private var selection: String?
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            Text("Extensions come from Raycast's open source repository. Some need Raycast features Floe doesn't have yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .task {
            // The catalog may be here already, and when a load brings it, the change asks again below.
            search()
            await store.loadCatalog()
        }
        .onChange(of: query) { _, _ in search() }
        .onChange(of: store.catalog) { _, _ in search() }
        .alert(store.menuBarOffer?.title ?? "", isPresented: offerIsShown, presenting: store.menuBarOffer) { offer in
            if offer.ready.isEmpty {
                Button("OK", role: .cancel) { store.menuBarOffer = nil }
            } else {
                Button("Add to Menu Bar") {
                    settings.menuBarCommands.formUnion(offer.ready.map(\.id))
                }
                Button("Not Now", role: .cancel) { store.menuBarOffer = nil }
            }
        } message: { offer in
            Text(offer.message)
        }
    }

    private var offerIsShown: Binding<Bool> {
        Binding(get: { store.menuBarOffer != nil }, set: {
            if !$0 {
                store.menuBarOffer = nil
            }
        })
    }

    private func search() {
        matched = StoreSearch.results(store.catalog, query: query)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading, store.catalog.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading extensions…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.error, store.catalog.isEmpty {
            VStack(spacing: 8) {
                Text("Could not load the extension store.")
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await store.loadCatalog(force: true) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A plain list beside the details: a split view inside Settings' own split view collapses
            // its list and pushes the window wider.
            // Matched once for each pass: the list and its empty state read the same rows.
            let filtered = matched
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TextField("Search extensions", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .padding(10)
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered, id: \.name) { listing in
                                StoreRow(store: store, name: listing.name)
                                    .padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selection == listing.name ? Color.accentColor.opacity(0.2) : .clear)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selection == listing.name {
                                            selection = nil
                                        } else {
                                            selection = listing.name
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .overlay {
                        if filtered.isEmpty, !query.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
                if !(selection?.isEmpty ?? true) {
                    Divider()
                    Group {
                        if let name = selection {
                            StoreDetail(store: store, name: name)
                                .id(name)
                        } else {
                            Text("Select an extension to see its details.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

private struct StoreRow: View {
    @ObservedObject var store: ExtensionStore
    let name: String
    @State private var loaded: StoreDetails?
    @State private var updateAvailable = false

    var body: some View {
        // What an earlier row already learned shows at once, so typing does not blank the rows it keeps.
        let details = store.cachedDetails(for: name) ?? loaded
        VStack(spacing: 8) {
            StoreIcon(store: store, url: details?.iconURL, size: 40)
            VStack(spacing: 2) {
                Text(details?.title ?? name)
                    .lineLimit(1)
                Text(details?.description ?? " ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .multilineTextAlignment(.center)
            StoreActionButton(store: store, name: name, details: details, updateAvailable: updateAvailable)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .task(id: name) {
            loaded = await store.details(for: name, after: ExtensionStore.settleDelay)
            guard !Task.isCancelled else { return }
            if store.isInstalled(name) {
                updateAvailable = await store.hasUpdate(name)
            }
        }
    }
}

private struct StoreActionButton: View {
    @ObservedObject var store: ExtensionStore
    let name: String
    var details: StoreDetails?
    var updateAvailable: Bool

    var body: some View {
        Group {
            if store.busy.contains(name) {
                ProgressView()
                    .controlSize(.small)
            } else if !store.isInstalled(name) {
                Button("Install") {
                    Task { await store.install(name) }
                }
            } else if updateAvailable {
                Button("Update") {
                    Task { await store.update(name) }
                }
            } else {
                Text("Installed")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }
}

private struct StoreDetail: View {
    @ObservedObject var store: ExtensionStore
    let name: String
    @State private var details: StoreDetails?
    @State private var updateAvailable = false

    private var githubURL: URL? {
        URL(string: "https://github.com/raycast/extensions/tree/main/extensions/\(name)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    StoreIcon(store: store, url: details?.iconURL, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(details?.title ?? name)
                            .font(.title3.weight(.semibold))
                        if let author = details?.author, !author.isEmpty {
                            Text(author)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let description = details?.description, !description.isEmpty {
                    Text(description)
                }
                HStack(spacing: 8) {
                    if store.busy.contains(name) {
                        ProgressView().controlSize(.small)
                    } else if !store.isInstalled(name) {
                        Button("Install") {
                            Task { await store.install(name) }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        if updateAvailable {
                            Button("Update") {
                                Task { await store.update(name) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Remove") {
                            store.remove(name)
                        }
                    }
                    if let githubURL {
                        Link("View on GitHub", destination: githubURL)
                    }
                }
                if let error = store.error, store.busy.contains(name) == false {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let details, !details.commands.isEmpty {
                    Text("Commands")
                        .font(.headline)
                    ForEach(details.commands) { command in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(command.title)
                            if let description = command.description, !description.isEmpty {
                                Text(description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .task(id: name) {
            details = await store.details(for: name)
            if store.isInstalled(name) {
                updateAvailable = await store.hasUpdate(name)
            } else {
                updateAvailable = false
            }
        }
    }
}

private struct StoreIcon: View {
    let store: ExtensionStore
    let url: URL?
    let size: CGFloat
    @State private var file: String?

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size / 5, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .overlay(Image(systemName: "puzzlepiece.extension").font(.system(size: size * 0.45)).foregroundStyle(.secondary))
    }

    var body: some View {
        Group {
            if let file = url.flatMap(store.knownIconFile(for:)) ?? file {
                IconThumbnailView(source: .file(path: file), size: size) { $0.resizable().scaledToFit() }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 5, style: .continuous))
        .task(id: url) {
            file = nil
            if let url {
                file = await store.iconFile(for: url)
            }
        }
    }
}
