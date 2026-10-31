//
//  ExtensionGridViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// A Grid's tiles, section by section as its layout has them. Equatable on what they show, as the list's rows are.
struct GridRows: View, Equatable {
    let session: ExtensionSession
    let rows: [Row]
    /// Stands for `rows` in the comparison, as it does for the list.
    let version: Int
    let selectedID: Int?
    let layout: GridLayout

    static func == (lhs: GridRows, rhs: GridRows) -> Bool {
        lhs.session === rhs.session && lhs.version == rhs.version && lhs.selectedID == rhs.selectedID && lhs.layout == rhs.layout
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(layout.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 8) {
                            if section.title != nil || section.subtitle != nil {
                                ListSectionHeading(title: section.title ?? "", isFirst: true, detail: section.subtitle)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: section.columns), alignment: .leading, spacing: 12) {
                                ForEach(section.items.map { (index: $0, row: rows[$0]) }, id: \.row.id) { index, row in
                                    tile(row, at: index, in: section)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: selectedID) {
                if let selectedID {
                    proxy.scrollTo(selectedID)
                }
            }
        }
    }

    private func tile(_ row: Row, at index: Int, in section: GridLayout.Section) -> some View {
        GridTile(node: row.node, assetsPath: session.command.assetsPath, selected: row.id == selectedID, aspectRatio: section.aspectRatio, fills: section.fills, inset: section.inset)
            .equatable()
            .onTapGesture(count: 2) {
                session.selection = index
                if let action = session.actions.first {
                    session.run(action)
                }
            }
            .onTapGesture { session.selection = index }
            .id(row.id)
            .onAppear {
                if index >= rows.count - 3 {
                    session.loadMore()
                }
            }
    }
}

/// One item: its content in a tile of the section's shape, then its title and subtitle.
struct GridTile: View, Equatable {
    let node: Node
    let assetsPath: String
    let selected: Bool
    let aspectRatio: Double
    let fills: Bool
    let inset: Double

    static func == (lhs: GridTile, rhs: GridTile) -> Bool {
        lhs.node.revision == rhs.node.revision && lhs.selected == rhs.selected && lhs.aspectRatio == rhs.aspectRatio
            && lhs.fills == rhs.fills && lhs.inset == rhs.inset && lhs.assetsPath == rhs.assetsPath
    }

    private static let shape = RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)

    var body: some View {
        // { value, tooltip } wraps the content with a tooltip; anything else is the content itself.
        let content = node.props["content"] as? [String: Any]
        let tooltip = content?["tooltip"] as? String
        let value = tooltip == nil ? node.props["content"] : content?["value"]
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        tileContent(value, in: geometry.size)
                    }
                }
                .background(.quinary, in: Self.shape)
                .clipShape(Self.shape)
                .overlay { Self.shape.strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5) }
                .thawSelectionCue(isSelected: selected, in: Self.shape)
                .help(tooltip ?? "")
            if let title = node.string("title") {
                HStack(spacing: 4) {
                    Text(title).font(ThawType.caption.weight(.medium)).lineLimit(1)
                    if let accessory = node.props["accessory"] as? [String: Any], let icon = accessory["icon"] {
                        Spacer(minLength: 0)
                        IconView(value: icon, assetsPath: assetsPath, size: 13)
                            .help(accessory["tooltip"] as? String ?? "")
                    }
                }
            }
            if let subtitle = node.string("subtitle") {
                Text(subtitle).font(ThawType.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// A color fills the tile; an image is as large as the fit and the inset let it be.
    @ViewBuilder
    private func tileContent(_ value: Any?, in size: CGSize) -> some View {
        if let color = Palette.color((value as? [String: Any])?["color"]) {
            color
        } else {
            let side = fills ? max(size.width, size.height) : min(size.width, size.height) * (1 - 2 * inset)
            IconView(value: value, assetsPath: assetsPath, size: side, isFramed: false)
                .frame(width: size.width, height: size.height)
        }
    }
}
