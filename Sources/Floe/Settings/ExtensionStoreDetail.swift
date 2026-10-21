//
//  ExtensionStoreDetail.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// The store's preview of one extension: what it is, what it looks like, and what each command does.
struct StoreDetail: View {
    @ObservedObject var store: ExtensionStore
    let name: String
    @State private var details: StoreDetails?
    @State private var updateAvailable = false
    @State private var screenshots: [StoreScreenshot] = []
    @State private var enlarged: StoreScreenshot?

    /// Long lines are hard to read, so a wide pane keeps its text to this width.
    private static let readableWidth: CGFloat = 620

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StoreDetailHeader(store: store, name: name, details: details, updateAvailable: $updateAvailable)
                if let description = details?.description, !description.isEmpty {
                    Text(description)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let details {
                    StoreFacts(details: details)
                }
                if !screenshots.isEmpty {
                    StoreScreenshotStrip(screenshots: screenshots) { enlarged = $0 }
                }
                if let details, !details.commands.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Commands")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(details.commands) { command in
                            StoreCommandCard(store: store, command: command, extensionIcon: details.iconURL)
                        }
                    }
                }
            }
            .frame(maxWidth: Self.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsPageHeading.leadingMargin - 8)
            .padding(.vertical, 14)
        }
        .sheet(item: $enlarged) { screenshot in
            StoreScreenshotSheet(screenshot: screenshot)
        }
        .task(id: name) {
            details = await store.details(for: name)
            updateAvailable = store.isInstalled(name) ? await store.hasUpdate(name) : false
        }
        .task(id: name) {
            // Only the pane that is open asks: the list's rows never fetch screenshots.
            for url in await store.screenshots(for: name) {
                guard !Task.isCancelled else { return }
                if let file = await store.iconFile(for: url), let screenshot = await StoreScreenshot.load(file) {
                    screenshots.append(screenshot)
                }
            }
        }
    }
}

/// The icon, the name and who made it, and what can be done with it.
private struct StoreDetailHeader: View {
    @ObservedObject var store: ExtensionStore
    let name: String
    let details: StoreDetails?
    @Binding var updateAvailable: Bool
    @Environment(\.openURL) private var openURL

    private var githubURL: URL? {
        URL(string: "https://github.com/raycast/extensions/tree/main/extensions/\(name)")
    }

    var body: some View {
        let installed = store.isInstalled(name)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                StoreIcon(store: store, url: details?.iconURL, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(details?.title ?? name)
                        .font(.title2.bold())
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if let author = details?.author, !author.isEmpty {
                        Text(author)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if updateAvailable {
                        StoreTag(text: String(localized: "Update available", bundle: .floe, comment: "A tag on an installed extension that has a newer version."), tint: .accentColor)
                    } else if installed {
                        StoreTag(text: String(localized: "Installed", bundle: .floe, comment: "Said of an extension that is already installed."))
                    }
                }
                .padding(.top, 4)
                Spacer(minLength: 8)
                actions(installed: installed)
                    .padding(.top, 6)
            }
            if let error = store.error, !store.busy.contains(name) {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private func actions(installed: Bool) -> some View {
        HStack(spacing: 6) {
            if store.busy.contains(name) {
                ProgressView()
                    .controlSize(.small)
            } else if !installed {
                Button("Install") {
                    Task { await store.install(name) }
                }
                .buttonStyle(.borderedProminent)
            } else if updateAvailable {
                Button("Update") {
                    Task {
                        await store.update(name)
                        updateAvailable = await store.hasUpdate(name)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Menu {
                if installed {
                    Button("Remove", role: .destructive) {
                        store.remove(name)
                    }
                }
                if let githubURL {
                    Button("View on GitHub") {
                        openURL(githubURL)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More"))
            .disabled(store.busy.contains(name))
        }
    }
}

/// The manifest's categories, how many commands there are, and whether something must be set before use.
private struct StoreFacts: View {
    let details: StoreDetails

    var body: some View {
        StoreTagFlow(spacing: 6) {
            ForEach(details.categories, id: \.self) { category in
                StoreTag(text: category)
            }
            Text(String(localized: "\(details.commands.count) commands", bundle: .floe, comment: "The placeholder is how many commands an extension has."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
            if details.needsSetup {
                StoreTag(text: String(localized: "Needs setup", bundle: .floe, comment: "A tag on an extension with a setting that must be filled in before it runs."), tint: .orange)
            }
        }
    }
}

private struct StoreCommandCard: View {
    let store: ExtensionStore
    let command: StoreCommand
    let extensionIcon: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StoreIcon(store: store, url: command.iconURL ?? extensionIcon, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(command.title)
                        .fontWeight(.medium)
                    Spacer(minLength: 0)
                    StoreTag(text: Self.modeLabel(command.mode))
                }
                if let description = command.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !command.arguments.isEmpty {
                    StoreTagFlow(spacing: 4) {
                        ForEach(command.arguments, id: \.name) { argument in
                            StoreTag(text: argument.placeholder ?? argument.name, symbol: "character.cursor.ibeam")
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
    }

    /// The tag for how a command runs.
    static func modeLabel(_ mode: String) -> String {
        switch mode {
        case "no-view": String(localized: "Background", bundle: .floe, comment: "A command that runs without a window of its own.")
        case "menu-bar": String(localized: "Menu Bar", bundle: .floe, comment: "A command that shows in the menu bar.")
        default: String(localized: "View", bundle: .floe, comment: "A command that opens its own view in the launcher.")
        }
    }
}

/// A small capsule of text, for the facts of an extension and its commands.
struct StoreTag: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Lays its views out in rows, starting a new row where the next one would not fit.
struct StoreTagFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += (rows[last].indices.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indices.append(index)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// A screenshot kept in the temporary folder, decoded at the size the strip draws it. Raycast's are 2000 pixels
/// wide, 10 MB each once decoded, so the full picture is never held.
struct StoreScreenshot: Identifiable {
    /// The longer side in pixels: the strip's width on a Retina display, and the sheet's.
    static let stripPixels = 576
    static let sheetPixels = 1440

    let file: String
    let image: CGImage
    var id: String {
        file
    }

    static func load(_ file: String) async -> StoreScreenshot? {
        await decoded(file, pixels: stripPixels).map { StoreScreenshot(file: file, image: $0) }
    }

    /// Decodes off the main thread, straight to the size asked for.
    @concurrent
    static func decoded(_ file: String, pixels: Int) async -> CGImage? {
        CGImageSourceCreateWithURL(URL(fileURLWithPath: file) as CFURL, nil)?.thumbnail(at: 0, maxPixelSize: pixels)
    }
}

/// The screenshots side by side, each opening larger when clicked.
private struct StoreScreenshotStrip: View {
    let screenshots: [StoreScreenshot]
    let open: (StoreScreenshot) -> Void

    /// Raycast's screenshots are 16:10.
    private static let height: CGFloat = 180
    private static let width = height * 1.6
    private static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(screenshots) { screenshot in
                    Button {
                        open(screenshot)
                    } label: {
                        Image(decorative: screenshot.image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: Self.width, height: Self.height)
                            .clipShape(Self.shape)
                            .overlay { Self.shape.strokeBorder(.separator.opacity(0.5), lineWidth: 0.5) }
                            .contentShape(Self.shape)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Show larger"))
                }
            }
        }
    }
}

/// One screenshot as large as the window allows, closed with Escape or Done. The larger picture is decoded when the
/// sheet opens and let go when it closes; the strip's stands in until it arrives.
private struct StoreScreenshotSheet: View {
    let screenshot: StoreScreenshot
    @State private var large: CGImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(decorative: large ?? screenshot.image, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: 720, maxHeight: 450)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .task { large = await StoreScreenshot.decoded(screenshot.file, pixels: StoreScreenshot.sheetPixels) }
    }
}
