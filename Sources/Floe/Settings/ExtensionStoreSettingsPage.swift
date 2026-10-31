//
//  ExtensionStoreSettingsPage.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

struct ExtensionStoreSettingsPage: View {
    @ObservedObject var store: ExtensionStore
    let settings: AppSettings
    @State private var query = ""
    /// The catalog against the query, as it was last worked out. The ranking runs when one of the two
    /// changes, not on every pass of the view, where a row's own state would ask for it again.
    @State private var matched: [StoreListing] = []
    @State private var selection: String?
    /// How wide the grid is, for how many tiles a row of it holds: the arrows move by rows.
    @State private var gridWidth: CGFloat = 0
    /// The field and the grid line up; a row's text, inside its highlight, then lines up with the page's title.
    private static let inset = SettingsPageHeading.leadingMargin - ThawSpacing.base
    private static let tileWidth: CGFloat = 160
    private let columns = [GridItem(.adaptive(minimum: tileWidth, maximum: 220), spacing: ThawSpacing.inset, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            // Over the list and the details rather than in either, which scroll on their own.
            SettingsPageHeader()
                .padding(.horizontal, SettingsPageHeading.leadingMargin)
                .padding(.top, SettingsPageHeading.topMargin)
            content
            Divider()
            Text("Extensions come from Raycast's open source repository. Some need Raycast features Floe doesn't have yet.")
                .font(ThawType.footnote)
                .foregroundStyle(ThawInk.supporting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ThawSpacing.inset)
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

    private func toggle(_ name: String) {
        selection = selection == name ? nil : name
    }

    /// Left and right step a tile, up and down a row of them. With none selected, any arrow selects the first.
    private func move(_ direction: MoveCommandDirection, in listings: [StoreListing]) {
        let perRow = max(1, Int((gridWidth + ThawSpacing.inset) / (Self.tileWidth + ThawSpacing.inset)))
        let offset = switch direction {
        case .left: -1
        case .right: 1
        case .up: -perRow
        case .down: perRow
        @unknown default: 0
        }
        if let next = listings.item(stepping: offset, from: { $0.name == selection }) {
            selection = next.name
        }
    }

    private func search() {
        matched = StoreSearch.results(store.catalog, query: query)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading, store.catalog.isEmpty {
            ThawEmptyState(systemImage: "bag", title: .floe("Loading extensions…"), isLoading: true)
        } else if let error = store.error, store.catalog.isEmpty {
            ThawEmptyState(
                systemImage: "exclamationmark.triangle",
                title: .floe("Could not load the extension store."),
                caption: .verbatim(error),
                actionTitle: .floe("Try Again")
            ) {
                Task { await store.loadCatalog(force: true) }
            }
        } else {
            // A plain list beside the details: a split view inside Settings' own split view collapses
            // its list and pushes the window wider.
            // Matched once for each pass: the list and its empty state read the same rows.
            let filtered = matched
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Named for the store, so it is not taken for the settings search in the sidebar.
                    SettingsFilterField(prompt: .floe("Search Raycast extensions"), text: $query)
                        .padding(.horizontal, Self.inset)
                        .padding(.vertical, ThawSpacing.row)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: ThawSpacing.inset) {
                                ForEach(filtered, id: \.name) { listing in
                                    // A tap and not a Button: the tile holds the Install button of its own.
                                    StoreRow(store: store, name: listing.name)
                                        .padding(.horizontal, ThawSpacing.base)
                                        .selectedRowBackground(selection == listing.name)
                                        .onTapGesture { toggle(listing.name) }
                                        .accessibilityAction { toggle(listing.name) }
                                        .id(listing.name)
                                }
                            }
                            .padding(.horizontal, Self.inset)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                        }
                        .scrollEdgeEffectStyle(.soft, for: .top)
                        // A tile chosen by the arrow keys stays in sight.
                        .onChange(of: selection) {
                            if let selection {
                                withAnimation { proxy.scrollTo(selection) }
                            }
                        }
                        .focusable()
                        .focusEffectDisabled()
                        .onMoveCommand { move($0, in: filtered) }
                    }
                    .overlay {
                        if filtered.isEmpty, !query.isEmpty {
                            NoMatchesState(query: query)
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
                                .foregroundStyle(ThawInk.supporting)
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
        VStack(spacing: ThawSpacing.base) {
            StoreIcon(store: store, url: details?.iconURL, size: 40)
            VStack(spacing: ThawSpacing.hairline) {
                Text(details?.title ?? name)
                    .lineLimit(1)
                Text(details?.description ?? " ")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .lineLimit(2, reservesSpace: true)
            }
            .multilineTextAlignment(.center)
            StoreActionButton(store: store, name: name, details: details, updateAvailable: updateAvailable)
        }
        .padding(ThawSpacing.row)
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
                .buttonStyle(.settingsGlass)
            } else if updateAvailable {
                Button("Update") {
                    Task { await store.update(name) }
                }
                .buttonStyle(.settingsGlass)
            } else {
                Text("Installed")
                    .foregroundStyle(ThawInk.supporting)
            }
        }
        .font(ThawType.footnote)
        .controlSize(.small)
    }
}

/// An extension's icon, or a puzzle piece until it is here.
struct StoreIcon: View {
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
