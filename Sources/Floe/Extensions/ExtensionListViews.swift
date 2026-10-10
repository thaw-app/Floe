//
//  ExtensionListViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

// MARK: List

struct ListBody: View {
    @ObservedObject var session: ExtensionSession
    let view: Node

    var body: some View {
        let rows = session.rows
        let selected = session.selectedRow
        if rows.isEmpty {
            let empty = view.content.first { $0.type == "EmptyView" }
            if view.bool("isLoading") {
                Color.clear
            } else {
                Placeholder(title: empty?.string("title") ?? String(localized: "No Results", bundle: .floe), detail: empty?.string("description"))
            }
        } else {
            HStack(spacing: 0) {
                ListRows(session: session, rows: rows, version: session.rowsVersion, selectedID: selected?.id, compact: view.bool("isShowingDetail"))
                    .equatable()
                if view.bool("isShowingDetail"), let detail = selected?.node.slot("detail") {
                    Divider()
                    DetailBody(node: detail, assetsPath: session.command.assetsPath)
                        .equatable()
                        .frame(width: 430)
                }
            }
        }
    }
}

/// The rows. Equatable on what they show, so a render that left them alone, or a toast, does not walk the list.
struct ListRows: View, Equatable {
    let session: ExtensionSession
    let rows: [Row]
    /// Stands for `rows` in the comparison: SwiftUI asks once for every row on show.
    let version: Int
    let selectedID: Int?
    let compact: Bool

    static func == (lhs: ListRows, rhs: ListRows) -> Bool {
        lhs.session === rhs.session && lhs.version == rhs.version && lhs.selectedID == rhs.selectedID && lhs.compact == rhs.compact
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        // One view per row, title included: a lazy stack walks the whole list when rows vary in count.
                        VStack(alignment: .leading, spacing: 0) {
                            if let title = row.sectionTitle, index == 0 || rows[index - 1].sectionTitle != title {
                                Text(title)
                                    .font(ThawType.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, index == 0 ? 2 : 10)
                                    .padding(.bottom, 4)
                            }
                            ListRow(node: row.node, assetsPath: session.command.assetsPath, selected: row.id == selectedID, compact: compact)
                                .equatable()
                                .onTapGesture(count: 2) {
                                    session.selection = index
                                    if let action = session.actions.first {
                                        session.run(action)
                                    }
                                }
                                .onTapGesture { session.selection = index }
                        }
                        .id(row.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedID) {
                if let selectedID {
                    proxy.scrollTo(selectedID)
                }
            }
        }
    }
}

/// One row, drawn again only when the host sent its item anew or its selection changed.
struct ListRow: View, Equatable {
    let node: Node
    let assetsPath: String
    let selected: Bool
    let compact: Bool

    static func == (lhs: ListRow, rhs: ListRow) -> Bool {
        lhs.node.revision == rhs.node.revision && lhs.selected == rhs.selected && lhs.compact == rhs.compact && lhs.assetsPath == rhs.assetsPath
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = node.props["icon"] ?? node.props["content"] {
                IconView(value: icon, assetsPath: assetsPath, size: 18)
            }
            Text(node.string("title") ?? "").lineLimit(1)
            if !compact, let subtitle = node.string("subtitle") {
                Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !compact {
                ForEach(Array((node.props["accessories"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, accessory in
                    AccessoryView(accessory: accessory, assetsPath: assetsPath)
                }
            }
        }
        .font(ThawType.body)
        .modifier(RowBackground(selected: selected))
    }
}

struct AccessoryView: View {
    let accessory: [String: Any]
    let assetsPath: String

    var body: some View {
        HStack(spacing: 4) {
            if let icon = accessory["icon"] {
                IconView(value: icon, assetsPath: assetsPath, size: 13)
            }
            if let text = PropFormat.text(accessory["text"]) {
                Text(text).foregroundStyle(Palette.color(PropFormat.color(accessory["text"])) ?? .secondary)
            }
            if let tag = PropFormat.text(accessory["tag"]) {
                let color = Palette.color(PropFormat.color(accessory["tag"])) ?? .secondary
                Text(tag)
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: .rect(cornerRadius: 5))
            }
            if let date = PropFormat.date(accessory["date"]) {
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }
}

// MARK: Detail

/// A detail pane, drawn again only when the host sent it anew.
struct DetailBody: View, Equatable {
    let node: Node
    let assetsPath: String

    static func == (lhs: DetailBody, rhs: DetailBody) -> Bool {
        lhs.node.revision == rhs.node.revision && lhs.assetsPath == rhs.assetsPath
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                MarkdownTextView(text: node.string("markdown") ?? "")
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let metadata = node.slot("metadata") {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(metadata.content) { MetadataRow(node: $0, assetsPath: assetsPath) }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 210)
            }
        }
    }
}

struct MetadataRow: View {
    let node: Node
    let assetsPath: String

    var body: some View {
        if node.type == "Metadata.Separator" {
            Divider()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(node.string("title") ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                switch node.type {
                case "Metadata.Link":
                    if let target = node.string("target"), let url = URL(string: target) {
                        Link(node.string("text") ?? target, destination: url)
                    }
                case "Metadata.TagList":
                    HStack(spacing: 4) {
                        ForEach(node.content) { tag in
                            let color = Palette.color(tag.props["color"]) ?? .secondary
                            Text(tag.string("text") ?? "")
                                .foregroundStyle(color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.15), in: .rect(cornerRadius: 5))
                        }
                    }
                default:
                    HStack(spacing: 5) {
                        if let icon = node.props["icon"] {
                            IconView(value: icon, assetsPath: assetsPath, size: 13)
                        }
                        Text(PropFormat.text(node.props["text"]) ?? "").textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 12))
        }
    }
}
