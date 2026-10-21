//
//  ThawTabStrip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A tab that names itself, for ThawTabStrip(selection:tabs:).
public nonisolated protocol ThawTab: Hashable {
    var title: LocalizedStringKey { get }
    var systemImage: String { get }
}

/// Tabs, each an icon and its name, in one glass capsule like Xcode's navigator bar,
/// switching what a page shows below it. Settings pages use it where a segmented
/// control is not allowed. The tabs share the strip's width evenly, so it fills the
/// page it heads instead of sitting as a small pill in a wide card.
public struct ThawTabStrip<Tab: Hashable>: View {
    public struct Item {
        let tab: Tab
        let title: LocalizedStringKey
        let systemImage: String

        public init(_ tab: Tab, title: LocalizedStringKey, systemImage: String) {
            self.tab = tab
            self.title = title
            self.systemImage = systemImage
        }
    }

    @Binding private var selection: Tab
    private let items: [Item]

    public init(selection: Binding<Tab>, items: [Item]) {
        _selection = selection
        self.items = items
    }

    /// Tabs that carry their own name and symbol, in the order given.
    public init(selection: Binding<Tab>, tabs: [Tab]) where Tab: ThawTab {
        self.init(selection: selection, items: tabs.map { Item($0, title: $0.title, systemImage: $0.systemImage) })
    }

    public var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                tabButton(item)
            }
        }
        .padding(ThawSpacing.tight)
        .frame(maxWidth: .infinity)
        .thawGlass(.control, in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ item: Item) -> some View {
        let isSelected = item.tab == selection
        let shape = Capsule(style: .continuous)
        return Button {
            selection = item.tab
        } label: {
            // Styled on each part: a section header sets its own text colour over the label's.
            let style = isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
            Label {
                Text(item.title)
                    .font(ThawType.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(style)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(style)
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, ThawSpacing.inset)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            .thawSelectedFill(isSelected, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .thawSelectionCue(isSelected: isSelected, in: shape)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
