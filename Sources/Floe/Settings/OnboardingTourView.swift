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

    /// Row heights at the default text size, scaled so captions do not clip at larger text.
    @ScaledMetric(relativeTo: .body) private var largeRowHeight: CGFloat = 164
    @ScaledMetric(relativeTo: .body) private var smallRowHeight: CGFloat = 126

    private var hotkeyText: String {
        if let hotkey = settings.toggleHotkey {
            return String(
                localized: "Press \(hotkey.displayValue) to show or hide Floe from any app. You can change the hotkey in Settings.",
                bundle: .floe,
                comment: "The placeholder is a keyboard shortcut."
            )
        }
        return String(localized: "Open Floe from its menu bar icon. You can set a hotkey in Settings.", bundle: .floe)
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

    private var grid: some View {
        // Four equal columns, measured once: a Grid widens a column to fit its longest title.
        GeometryReader { geometry in
            let column = (geometry.size.width - ThawSpacing.gutter * 3) / 4
            VStack(spacing: ThawSpacing.gutter) {
                HStack(spacing: ThawSpacing.gutter) {
                    tile(
                        0,
                        span: 2,
                        column: column,
                        large: true,
                        symbol: "keyboard",
                        title: String(localized: "Open it with a hotkey", bundle: .floe),
                        caption: hotkeyText,
                        demo: hotkeyDemo
                    )
                    tile(
                        1,
                        span: 2,
                        column: column,
                        large: true,
                        symbol: "puzzlepiece.extension",
                        title: String(localized: "Run Raycast extensions", bundle: .floe),
                        caption: String(localized: "Floe runs the extensions in its own folder and the ones you have installed in Raycast.", bundle: .floe),
                        demo: .search(query: "github", rows: [
                            TourRow(symbol: "puzzlepiece.extension", title: "My Pull Requests", trailing: "GitHub"),
                            TourRow(symbol: "puzzlepiece.extension", title: "Search Repositories", trailing: "GitHub"),
                        ])
                    )
                }
                HStack(spacing: ThawSpacing.gutter) {
                    tile(
                        2,
                        span: 2,
                        column: column,
                        symbol: "bubble.left.and.text.bubble.right",
                        title: String(localized: "Ask AI", bundle: .floe),
                        caption: String(localized: "`ask` and a question, answered by a tool you are signed in to, Apple Intelligence or an API. A switch keeps it all on your Mac.", bundle: .floe, comment: "A tile of the welcome tour. ask is the keyword typed in the search."),
                        demo: .ask(query: "ask what is a tide", marks: AIMark.all)
                    )
                    tile(
                        3,
                        span: 1,
                        column: column,
                        symbol: "doc.on.clipboard",
                        title: String(localized: "Clipboard history", bundle: .floe),
                        caption: String(localized: "Your last 300 copies. Return pastes one.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .search(query: "clip", rows: [TourRow(symbol: "doc.on.clipboard", title: String(localized: "Clipboard History", bundle: .floe))])
                    )
                    tile(
                        4,
                        span: 1,
                        column: column,
                        symbol: "equal.square",
                        title: String(localized: "Calculator", bundle: .floe),
                        caption: String(localized: "Sums, units and dates as you type them.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .search(query: "200 + 10%", rows: [TourRow(symbol: "equal", title: "220")])
                    )
                }
                HStack(spacing: ThawSpacing.gutter) {
                    tile(
                        5,
                        span: 1,
                        column: column,
                        symbol: "note.text",
                        title: String(localized: "Notes", bundle: .floe, comment: "A tile of the welcome tour."),
                        caption: String(localized: "`note` writes to your notes app. Floating Note stays on top.", bundle: .floe, comment: "A tile of the welcome tour. note is the keyword typed in the search."),
                        demo: .search(query: "note buy milk", rows: [TourRow(symbol: "note.text", title: String(localized: "Add to Notes", bundle: .floe, comment: "A result row in a demo of the welcome tour."))])
                    )
                    tile(
                        6,
                        span: 1,
                        column: column,
                        symbol: "apple.terminal",
                        title: String(localized: "Shell commands", bundle: .floe, comment: "A tile of the welcome tour."),
                        caption: String(localized: "`>` and a command runs it. ⌘Return opens your terminal.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .search(query: "> git status", rows: [TourRow(symbol: "apple.terminal", title: "git status", trailing: "↩")])
                    )
                    tile(
                        7,
                        span: 1,
                        column: column,
                        symbol: "text.quote",
                        title: String(localized: "Snippets", bundle: .floe, comment: "A tile of the welcome tour."),
                        caption: String(localized: "Text that expands as you type, and quicklinks you open by name.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .search(query: "docs", rows: [TourRow(symbol: "link", title: String(localized: "Docs", bundle: .floe, comment: "A result row in a demo of the welcome tour: a quicklink."), trailing: String(localized: "Quicklink", bundle: .floe, comment: "A result row in a demo of the welcome tour."))])
                    )
                    tile(
                        8,
                        span: 1,
                        column: column,
                        symbol: "app.badge.checkmark",
                        title: String(localized: "Your own apps", bundle: .floe, comment: "A tile of the welcome tour."),
                        caption: String(localized: "Files open in your editor and links in your browser.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .search(query: "~/Downloads", rows: [TourRow(symbol: "folder", title: "Downloads", trailing: "↩")])
                    )
                }
                HStack(spacing: ThawSpacing.gutter) {
                    tile(
                        9,
                        span: 2,
                        column: column,
                        symbol: "menubar.rectangle",
                        title: String(localized: "Menus and windows", bundle: .floe, comment: "A tile of the welcome tour."),
                        caption: String(localized: "Search the menu bar and the menus of the app in front, and switch windows. These need Accessibility.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .search(query: "menu new", rows: [TourRow(symbol: "menubar.rectangle", title: "New Window", trailing: "File  ⌘N")])
                    )
                    tile(
                        10,
                        span: 1,
                        column: column,
                        symbol: "icloud",
                        title: String(localized: "iCloud sync", bundle: .floe, comment: "A tile of the welcome tour."),
                        caption: String(localized: "Aliases, hotkeys and settings, the same on all your Macs.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .sync
                    )
                    tile(
                        11,
                        span: 1,
                        column: column,
                        symbol: "snowflake",
                        title: String(localized: "Works with Thaw", bundle: .floe, comment: "A tile of the welcome tour."),
                        caption: String(localized: "Thaw's actions are in the search, and Floe can follow its look.", bundle: .floe, comment: "A tile of the welcome tour."),
                        demo: .search(query: "zen", rows: [TourRow(symbol: "moon", title: "Zen Mode", trailing: "Thaw")])
                    )
                }
            }
        }
        .frame(height: largeRowHeight + smallRowHeight * 3 + ThawSpacing.gutter * 3)
    }

    // swiftlint:disable:next function_parameter_count
    private func tile(_ index: Int, span: Int, column: CGFloat, large: Bool = false, symbol: String, title: String, caption: String, demo: TourDemo) -> some View {
        OnboardingTourTile(symbol: symbol, title: title, caption: caption, demo: demo, index: index, appeared: appeared)
            .frame(width: column * CGFloat(span) + ThawSpacing.gutter * CGFloat(span - 1), height: large ? largeRowHeight : smallRowHeight)
    }
}
