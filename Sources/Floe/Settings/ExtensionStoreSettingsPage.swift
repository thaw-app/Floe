//
//  ExtensionStoreSettingsPage.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

struct ExtensionStoreSettingsPage: View {
    @ObservedObject private var store: ExtensionStore = .shared
    @State private var query = ""
    @State private var selection: String?

    init() {}

    private var filtered: [StoreListing] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.catalog }
        return store.catalog.filter { listing in
            if listing.name.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            guard let details = store.cachedDetails(for: listing.name) else { return false }
            return details.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

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
        .navigationTitle("Extension Store")
        .task {
            await store.loadCatalog()
        }
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
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TextField("Search extensions", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .padding(10)
                    List(filtered, selection: $selection) { listing in
                        StoreRow(name: listing.name)
                            .tag(listing.name)
                    }
                    .listStyle(.inset)
                    .overlay {
                        if filtered.isEmpty, !query.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
                .frame(width: 300)
                Divider()
                Group {
                    if let name = selection {
                        StoreDetail(name: name)
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

private struct StoreRow: View {
    @ObservedObject private var store: ExtensionStore = .shared
    let name: String
    @State private var details: StoreDetails?
    @State private var updateAvailable = false

    var body: some View {
        HStack(spacing: 8) {
            StoreIcon(url: details?.iconURL, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(details?.title ?? name)
                    .lineLimit(1)
                if let description = details?.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            StoreActionButton(name: name, details: details, updateAvailable: updateAvailable)
        }
        .task(id: name) {
            details = await store.details(for: name)
            if store.isInstalled(name) {
                updateAvailable = await store.hasUpdate(name)
            }
        }
    }
}

private struct StoreActionButton: View {
    @ObservedObject private var store: ExtensionStore = .shared
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
    @ObservedObject private var store: ExtensionStore = .shared
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
                    StoreIcon(url: details?.iconURL, size: 48)
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
    let url: URL?
    let size: CGFloat

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size / 5, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .overlay(Image(systemName: "puzzlepiece.extension").font(.system(size: size * 0.45)).foregroundStyle(.secondary))
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 5, style: .continuous))
    }
}
