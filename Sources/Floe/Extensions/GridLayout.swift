//
//  GridLayout.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Foundation

/// A Grid's items as Raycast lays them out: its sections one under another, each in lines of its own number of
/// columns, with the tile shape, fit and inset the section or the grid asks for.
nonisolated struct GridLayout: Equatable {
    struct Section: Equatable {
        /// Where the section's items start among the rows, and how many there are.
        let start: Int
        let count: Int
        let title: String?
        let subtitle: String?
        let columns: Int
        /// Width over height of a tile.
        let aspectRatio: Double
        /// Whether an image fills its tile, cropped, or fits inside it.
        let fills: Bool
        /// The space around an image, as a share of the tile's side.
        let inset: Double

        var items: Range<Int> {
            start ..< start + count
        }
    }

    let sections: [Section]

    init(view: Node, rows: [Row]) {
        let sectionNodes = Dictionary(view.content.filter { $0.type.hasSuffix(".Section") }.map { ($0.id, $0) }) { first, _ in first }
        sections = rows.indices.chunked(on: { rows[$0].sectionID }).map { id, items in
            let node = id.flatMap { sectionNodes[$0] }
            func prop(_ key: String) -> Any? {
                node?.props[key] ?? view.props[key]
            }
            return Section(
                start: items.lowerBound,
                count: items.count,
                title: node?.string("title"),
                subtitle: node?.string("subtitle"),
                columns: Self.columns(prop("columns"), itemSize: prop("itemSize")),
                aspectRatio: Self.aspectRatio(prop("aspectRatio")),
                fills: prop("fit") as? String == "fill",
                inset: Self.inset(prop("inset"))
            )
        }
    }

    /// Raycast's default is five columns; the older `itemSize` names three sizes of tile.
    static func columns(_ value: Any?, itemSize: Any?) -> Int {
        if let columns = value as? Int {
            return min(max(columns, 1), 8)
        }
        switch itemSize as? String {
        case "small": return 8
        case "large": return 3
        default: return 5
        }
    }

    /// "1", "3/2", "16/9" and the like; a square for anything else.
    static func aspectRatio(_ value: Any?) -> Double {
        guard let text = value as? String else { return 1 }
        let parts = text.split(separator: "/").compactMap { Double($0) }
        guard let width = parts.first, width > 0 else { return 1 }
        let height = parts.count > 1 ? parts[1] : 1
        return height > 0 ? width / height : 1
    }

    static func inset(_ value: Any?) -> Double {
        switch value as? String {
        case "small": 0.06
        case "medium": 0.12
        case "large": 0.2
        default: 0
        }
    }

    /// ← and →: the item before or after, across lines and sections.
    func moved(from index: Int, across delta: Int) -> Int {
        let count = sections.last.map { $0.start + $0.count } ?? 0
        return max(0, min(index + delta, count - 1))
    }

    /// ↑ and ↓: the item in the same column a line up or down, into the next section when the line is its last.
    /// A line with fewer items lands on its last; past the first or last line, the selection stays.
    func moved(from index: Int, lines: Int) -> Int {
        guard var sectionIndex = sections.firstIndex(where: { $0.items.contains(index) }) else { return index }
        var section = sections[sectionIndex]
        let column = (index - section.start) % section.columns
        var line = (index - section.start) / section.columns
        for _ in 0 ..< min(abs(lines), 10000) {
            let lineCount = (section.count + section.columns - 1) / section.columns
            if lines > 0, line + 1 < lineCount {
                line += 1
            } else if lines > 0, sectionIndex + 1 < sections.count {
                sectionIndex += 1
                section = sections[sectionIndex]
                line = 0
            } else if lines < 0, line > 0 {
                line -= 1
            } else if lines < 0, sectionIndex > 0 {
                sectionIndex -= 1
                section = sections[sectionIndex]
                line = (section.count - 1) / section.columns
            } else {
                break
            }
        }
        return section.start + min(line * section.columns + min(column, section.columns - 1), section.count - 1)
    }
}
