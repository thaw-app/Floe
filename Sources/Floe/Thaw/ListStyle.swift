//
//  ListStyle.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The settings sidebar's touches, for every list: the shared icon box, the selected fill, the group headings and the
/// arrow keys. The panel's lists keep their own glass selection and share the rest.
enum ListStyle {
    /// The box every row's icon sits in, so the names line up whatever the icon.
    static let iconBox: CGFloat = 18
    /// An app's or an extension's own icon is a little smaller than the box, to weigh what a symbol weighs.
    static let imageSize: CGFloat = 16
    static let symbolFont = Font.system(size: 15, weight: .regular)
    static let rowHeight: CGFloat = 32
    static let rowShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    /// How much an icon that is off fades.
    static let dimmedIconOpacity = 0.5
}

/// A row's icon in the shared box: a symbol in the secondary colour, or an icon of its own a little smaller.
struct ListRowIcon: View {
    enum Source {
        case symbol(String)
        /// An extension's or an app's icon, as `IconView` reads it.
        case icon(Any?, assetsPath: String)
    }

    let source: Source
    var isDimmed = false

    var body: some View {
        Group {
            switch source {
            case let .symbol(name):
                Image(systemName: name)
                    .font(ListStyle.symbolFont)
                    .foregroundStyle(.secondary)
            case let .icon(value, assetsPath):
                IconView(value: value, assetsPath: assetsPath, size: ListStyle.imageSize)
            }
        }
        .opacity(isDimmed ? ListStyle.dimmedIconOpacity : 1)
        .frame(width: ListStyle.iconBox, height: ListStyle.iconBox)
    }
}

/// The sidebar's selected row: a light gray fill with a faint edge, the same whether the window is key or not,
/// under a label that keeps its own colour. The row answers clicks across the whole shape.
struct SelectedRowBackground: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    ListStyle.rowShape
                        .fill(Color.primary.opacity(0.1))
                        .overlay(ListStyle.rowShape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                }
            }
            .contentShape(ListStyle.rowShape)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    func selectedRowBackground(_ isSelected: Bool) -> some View {
        modifier(SelectedRowBackground(isSelected: isSelected))
    }

    /// The up and down arrows move the selection once the list has focus, the way a List's do. `move` is handed
    /// -1 or 1.
    func movesSelectionWithArrows(_ move: @escaping (Int) -> Void) -> some View {
        focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: move(-1)
                case .down: move(1)
                default: break
                }
            }
    }
}

/// The small uppercase name over a group of rows. Room above it sets the groups apart, except over the first,
/// which has the list's own margin.
struct ListSectionHeading: View {
    let title: String
    var isFirst = false
    /// A few words after the name, as written: an extension's section subtitle.
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.compact) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, isFirst ? ThawSpacing.tight : ThawSpacing.gutter)
        .padding(.bottom, ThawSpacing.tight)
        .padding(.leading, ThawSpacing.row)
        .accessibilityAddTraits(.isHeader)
    }
}

extension Array {
    /// The item `offset` away from the current one, for the arrow keys: the first item when none is current yet,
    /// and nil past either end, where the selection stays.
    func item(stepping offset: Int, from isCurrent: (Element) -> Bool) -> Element? {
        guard let current = firstIndex(where: isCurrent) else { return first }
        return indices.contains(current + offset) ? self[current + offset] : nil
    }
}
