//
//  OnboardingTourView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The middle of onboarding, in Thaw's bento style: what Floe does, each tile a small demo, before it asks for anything.
struct OnboardingTourView: View {
    @ObservedObject var settings: AppSettings

    let continueTitle: String
    var onContinue: () -> Void

    @State private var appeared = false

    /// A row's height at the default text size, scaled so captions do not clip at larger text.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 138

    private var hotkeyText: String {
        if let hotkey = settings.toggleHotkey {
            return String(localized: "Press \(hotkey.displayValue) in any app. Change it in Settings.", bundle: .floe, comment: "A tile of the welcome tour. The placeholder is a keyboard shortcut.")
        }
        return String(localized: "Open Floe from its menu bar icon, or set a hotkey.", bundle: .floe, comment: "A tile of the welcome tour.")
    }

    /// The hotkey's keys as they are printed on the keyboard, or a search for an app when there is no hotkey.
    private var hotkeyDemo: TourDemo {
        guard let hotkey = settings.toggleHotkey else {
            return .search(query: "safari", rows: [TourRow(symbol: "safari", title: "Safari")])
        }
        return .keys(hotkey.modifiers.symbolicValue.map(String.init) + [hotkey.key.stringValue.capitalized])
    }

    var body: some View {
        VStack(spacing: ThawSpacing.inset) {
            Text("What Floe does")
                .font(ThawType.display)
                .padding(.top, ThawSpacing.section)

            grid
                .padding(.horizontal, ThawSpacing.section)

            HStack(spacing: ThawSpacing.gutter) {
                Text("Type ? in the search to see every keyword.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onContinue) {
                    Text(verbatim: continueTitle)
                        .font(ThawType.heading)
                        .frame(minWidth: 140, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, ThawSpacing.section)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .onAppear {
            Task { @MainActor in appeared = true }
        }
    }

    /// One tile of the tour: what it is called, a line on it, and the demo it plays.
    private struct Tile {
        let symbol: String
        let title: String
        let caption: String
        let demo: TourDemo
    }

    private var tiles: [Tile] {
        [
            Tile(symbol: "keyboard", title: String(localized: "Hotkey", bundle: .floe, comment: "A tile of the welcome tour."), caption: hotkeyText, demo: hotkeyDemo),
            Tile(
                symbol: "puzzlepiece.extension",
                title: String(localized: "Extensions", bundle: .floe, comment: "A tile of the welcome tour: Raycast extensions."),
                caption: String(localized: "Runs Raycast extensions, yours included.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "github", rows: [TourRow(symbol: "puzzlepiece.extension", title: "My Pull Requests", trailing: "GitHub")])
            ),
            Tile(
                symbol: "bubble.left.and.text.bubble.right",
                title: String(localized: "Ask AI", bundle: .floe),
                caption: String(localized: "`ask` and a question. It can stay on your Mac.", bundle: .floe, comment: "A tile of the welcome tour. ask is the keyword typed in the search."),
                // Four marks: the whole set is wider than one tile.
                demo: .ask(query: "ask what is a tide", marks: Array(AIMark.all.prefix(4)))
            ),
            Tile(
                symbol: "doc.on.clipboard",
                title: String(localized: "Clipboard history", bundle: .floe),
                caption: String(localized: "Your last 300 copies. Return pastes one.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "clip", rows: [TourRow(symbol: "doc.on.clipboard", title: String(localized: "Clipboard History", bundle: .floe))])
            ),
            Tile(
                symbol: "equal.square",
                title: String(localized: "Calculator", bundle: .floe),
                caption: String(localized: "Sums, units and dates as you type them.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "200 + 10%", rows: [TourRow(symbol: "equal", title: "220")])
            ),
            Tile(
                symbol: "note.text",
                title: String(localized: "Notes", bundle: .floe, comment: "A tile of the welcome tour."),
                caption: String(localized: "`note` writes to your notes app.", bundle: .floe, comment: "A tile of the welcome tour. note is the keyword typed in the search."),
                demo: .search(query: "note buy milk", rows: [TourRow(symbol: "note.text", title: String(localized: "Add to Notes", bundle: .floe, comment: "A result row in a demo of the welcome tour."))])
            ),
            Tile(
                symbol: "apple.terminal",
                title: String(localized: "Shell commands", bundle: .floe, comment: "A tile of the welcome tour."),
                caption: String(localized: "`>` and a command runs it in your shell.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "> git status", rows: [TourRow(symbol: "apple.terminal", title: "git status", trailing: "↩")])
            ),
            Tile(
                symbol: "text.quote",
                title: String(localized: "Snippets", bundle: .floe, comment: "A tile of the welcome tour."),
                caption: String(localized: "Text that expands as you type, and quicklinks.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "docs", rows: [TourRow(symbol: "link", title: String(localized: "Docs", bundle: .floe, comment: "A result row in a demo of the welcome tour: a quicklink."), trailing: String(localized: "Quicklink", bundle: .floe, comment: "A result row in a demo of the welcome tour."))])
            ),
            Tile(
                symbol: "app.badge.checkmark",
                title: String(localized: "Your own apps", bundle: .floe, comment: "A tile of the welcome tour."),
                caption: String(localized: "Files open in your editor and links in your browser.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "~/Downloads", rows: [TourRow(symbol: "folder", title: "Downloads", trailing: "↩")])
            ),
            Tile(
                symbol: "menubar.rectangle",
                title: String(localized: "Menus", bundle: .floe, comment: "A tile of the welcome tour."),
                caption: String(localized: "Search menus and windows. Uses Accessibility.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "menu new", rows: [TourRow(symbol: "menubar.rectangle", title: "New Window", trailing: "⌘N")])
            ),
            Tile(
                symbol: "icloud",
                title: String(localized: "iCloud sync", bundle: .floe, comment: "A tile of the welcome tour."),
                caption: String(localized: "Settings and aliases, the same on every Mac.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .sync
            ),
            Tile(
                symbol: "snowflake",
                title: String(localized: "Works with Thaw", bundle: .floe, comment: "A tile of the welcome tour."),
                caption: String(localized: "Thaw's actions in the search, and its look.", bundle: .floe, comment: "A tile of the welcome tour."),
                demo: .search(query: "zen", rows: [TourRow(symbol: "moon", title: "Zen Mode", trailing: "Thaw")])
            ),
        ]
    }

    /// Twelve tiles of one size, four to a row: three rows keep the window small.
    private static let columns = 4

    private var grid: some View {
        let tiles = tiles
        let rows = tiles.count / Self.columns
        // Equal columns measured from the width, not from what the captions would like: a Grid widens a column to
        // a caption's one-line length and pushes the window's content past its edges.
        return GeometryReader { geometry in
            let column = (geometry.size.width - ThawSpacing.gutter * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
            VStack(spacing: ThawSpacing.gutter) {
                ForEach(0 ..< rows, id: \.self) { row in
                    HStack(spacing: ThawSpacing.gutter) {
                        ForEach(0 ..< Self.columns, id: \.self) { position in
                            let index = row * Self.columns + position
                            let tile = tiles[index]
                            OnboardingTourTile(symbol: tile.symbol, title: tile.title, caption: tile.caption, demo: tile.demo, index: index, appeared: appeared)
                                .frame(width: column, height: rowHeight)
                        }
                    }
                }
            }
        }
        .frame(height: rowHeight * CGFloat(rows) + ThawSpacing.gutter * CGFloat(rows - 1))
    }
}
