//
//  ActionPanel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// A row of an action panel, an extension's or one of Floe's own, as the panel draws it.
struct ActionPanelEntry: Identifiable {
    let id: Int
    let title: String
    let icon: ListRowIcon.Source
    /// The heading it is listed under, as an extension's sections have one.
    var section: String?
    /// A line parts it from the row above, where Floe's own rows have a separator.
    var startsGroup = false
    var keys: Keys?
    var isSubmenu = false
    var isDestructive = false

    /// The keys that run it: an extension's as it declared them, in one cap, or Floe's own, a cap for each key as
    /// the bottom bar draws them.
    enum Keys {
        case label(String)
        case combination(KeyCombination)
    }
}

/// What an action panel lists and does. An extension's ⌘K and Floe's own drive the same card and keys.
@MainActor
protocol ActionPanelDriver: AnyObject {
    var panelEntries: [ActionPanelEntry] { get }
    /// Typed while the panel is open; filters every action, those in submenus included.
    var panelQuery: String { get set }
    var panelSelection: Int { get set }
    /// The open submenu's title; nil at the top.
    var panelSubmenuTitle: String? { get }
    /// Runs the row, or opens it when it is a submenu.
    func activatePanelEntry(at index: Int)
    func openPanelSubmenu(at index: Int)
    /// Esc and ←: the search is cleared first, then a submenu is left, then the panel closes.
    func stepBackInPanel()
    func closePanel()
}

extension ActionPanelDriver {
    /// While the panel is open, typing searches it, ↵ runs or opens a submenu, → opens one, ← and Esc step back.
    /// False for a key the panel leaves alone, such as one with ⌘, ⌃ or ⌥ held.
    func handleActionPanelKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            panelSelection = ViewState.clamp(panelSelection + delta, count: panelEntries.count)
            return true
        }
        switch event.keyCode {
        case 36, 76: activatePanelEntry(at: panelSelection)
        case 53, 123: stepBackInPanel()
        case 124: openPanelSubmenu(at: panelSelection)
        case 40 where flags == .command: closePanel()
        case 51: if !panelQuery.isEmpty {
                panelQuery.removeLast()
            }
        default:
            // Plain typing (Shift allowed) filters; anything with ⌘, ⌃ or ⌥ falls through to shortcuts.
            guard flags.subtracting(.shift).isEmpty, let characters = event.characters,
                  !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else {
                return false
            }
            panelQuery += characters
        }
        return true
    }
}

/// The action panel: a search line, then the rows under their headings, each with its icon and keys, on glass
/// above the bottom bar.
struct ActionPanelCard: View {
    let entries: [ActionPanelEntry]
    let query: String
    let submenuTitle: String?
    let selection: Int
    /// The height the panel can take, so a short panel scrolls its rows instead of cutting them off.
    var room: CGFloat = .infinity
    let activate: (Int) -> Void

    private static let width: CGFloat = 320
    /// Past this the actions scroll, and the one the arrows are on is kept in sight.
    private static let listHeight: CGFloat = 300
    private static let searchHeight: CGFloat = 30

    /// What the search line, the margins and the line under it leave of the room for the rows.
    private var listHeight: CGFloat {
        let chrome = Self.searchHeight + ThawSpacing.tight + 1 + 2 * ThawSpacing.compact + 2 * ThawSpacing.row
        return max(0, min(Self.listHeight, room - chrome))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ThawSpacing.compact) {
                if let submenuTitle {
                    Image(systemName: "chevron.left").font(ThawType.caption).foregroundStyle(.secondary)
                    Text(submenuTitle).fontWeight(.medium)
                }
                Text(query.isEmpty ? String(localized: "Search actions…", bundle: .floe) : query)
                    .foregroundStyle(query.isEmpty ? .tertiary : .primary)
                Spacer()
            }
            .padding(.horizontal, ThawSpacing.row)
            .frame(height: Self.searchHeight)
            Divider().padding(.bottom, ThawSpacing.tight)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if let section = entry.section, !section.isEmpty, index == 0 || entries[index - 1].section != section {
                                ListSectionHeading(title: section, isFirst: index == 0)
                            } else if entry.startsGroup {
                                Divider().padding(.vertical, ThawSpacing.tight)
                            }
                            row(entry, selected: index == selection)
                                .onTapGesture { activate(index) }
                                .id(index)
                        }
                        if entries.isEmpty {
                            Text("No matching actions").foregroundStyle(.secondary).padding(ThawSpacing.row)
                        }
                    }
                }
                .frame(maxHeight: listHeight)
                .fixedSize(horizontal: false, vertical: true)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onChange(of: selection) { proxy.scrollTo(selection) }
            }
        }
        .font(ThawType.body)
        .padding(ThawSpacing.compact)
        .frame(width: Self.width)
        .thawGlass(.borderlessPanel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .padding(ThawSpacing.row)
    }

    private func row(_ entry: ActionPanelEntry, selected: Bool) -> some View {
        HStack(spacing: ThawSpacing.base) {
            ListRowIcon(source: entry.icon)
            Text(entry.title)
                .foregroundStyle(entry.isDestructive ? Color.red : Color.primary)
                .lineLimit(1)
            Spacer()
            switch entry.keys {
            case let .label(label): KeyCap(label)
            case let .combination(keys): KeyCaps(keys: keys)
            case nil: EmptyView()
            }
            if entry.isSubmenu {
                Image(systemName: "chevron.right").font(ThawType.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(RowBackground(selected: selected))
    }
}
