//
//  ActionChoices.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ThawUI

/// What the user chose for one kind of result. A choice that names a row no longer on offer is passed over.
nonisolated struct KindActions: Codable, Equatable, Sendable {
    /// Tried in order: the first on offer is what Return does. Empty is what Floe does.
    var defaults: [ActionID] = []
    /// Left out of the Actions menu.
    var hidden: Set<ActionID> = []
    /// Keys that run a row while a result of the kind is selected, in place of Floe's for that row.
    var shortcuts: [ActionID: KeyCombination] = [:]
    /// Rows whose keys from Floe the user took off. Such a row has none unless the user gave it some.
    var clearedKeys: Set<ActionID> = []
    /// The Actions menu's rows in the order the user put them. Empty is Floe's order.
    var order: [ActionID] = []

    init() {
        // Nothing chosen.
    }

    private enum CodingKeys: String, CodingKey {
        case defaults, hidden, shortcuts, clearedKeys, order
    }

    /// A key that is missing reads as nothing chosen, so what an older version wrote still reads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaults = try container.decodeIfPresent([ActionID].self, forKey: .defaults) ?? []
        hidden = try container.decodeIfPresent(Set<ActionID>.self, forKey: .hidden) ?? []
        shortcuts = try container.decodeIfPresent([ActionID: KeyCombination].self, forKey: .shortcuts) ?? [:]
        clearedKeys = try container.decodeIfPresent(Set<ActionID>.self, forKey: .clearedKeys) ?? []
        order = try container.decodeIfPresent([ActionID].self, forKey: .order) ?? []
    }

    /// Hidden rows and cleared keys are written in order: a set's order changes from one launch to the next, and
    /// sync would read each change as an edit. Floe's own order is not written, so choices made before there was an
    /// order read as they were written.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaults, forKey: .defaults)
        try container.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(clearedKeys.map(\.rawValue).sorted(), forKey: .clearedKeys)
        if !order.isEmpty {
            try container.encode(order, forKey: .order)
        }
    }
}

extension AppSettings {
    /// The hotkeys Floe registers with the Mac: the one that opens it and those that run a command. The Mac takes
    /// them before the panel sees them, so no row's keys can be one.
    var floeHotkeys: Set<KeyCombination> {
        Set(commandHotkeys.values).union(toggleHotkey.map { [$0] } ?? [])
    }

    /// Takes the hotkeys off scripts that act on results. Such a script runs on the result selected, which a hotkey
    /// pressed anywhere has none of, and a hotkey left on it would still keep its keys from every row.
    func dropHotkeys(of actionScripts: [ScriptCommand]) {
        for script in actionScripts where commandHotkeys[script.id] != nil {
            commandHotkeys[script.id] = nil
        }
    }
}

extension ActionID: CodingKeyRepresentable {
    var codingKey: any CodingKey {
        rawValue.codingKey
    }

    init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}

/// The decisions behind the user's choices, as plain functions of the rows on offer: what Return runs, how the
/// Actions menu reads, and which keys the user can give a row.
enum AlternativeActionRules {
    /// Keys the launcher, the search field or the main menu already give a meaning to. The launcher takes its own by
    /// the key pressed, and the main menu its by what they type on the layout. Floe's keys for rows, such as ⌘Y, are
    /// not among them: they are a row's, and another row of a kind that lacks them can have them.
    static func reservedKeys(on layout: KeyLayout = .current) -> Set<KeyCombination> {
        // ⌘K, ⌘R, ⌘, and ⌘[.
        let launcher: [KeyCode] = [.k, .r, .comma, .leftBracket]
        let menu: [Character] = ["a", "c", "v", "x", "z", "h", "q", "w", "m", ","]
        var keys = Set(launcher.map { KeyCombination(key: $0, modifiers: .command) })
        keys.formUnion(menu.map { KeyCombination(key: layout.key(typing: $0), modifiers: .command) })
        keys.insert(KeyCombination(key: layout.key(typing: "z"), modifiers: [.command, .shift]))
        keys.insert(KeyCombination(key: layout.key(typing: "h"), modifiers: [.command, .option]))
        return keys
    }

    /// Keys the list and the search field use whatever else is held: they move or leave. Up on the top row recalls
    /// an earlier search before a row is asked. Return can be among a row's keys, with Command, since the views ask
    /// the selected row's keys before Return; Enter on the keypad is read as Return, so it is never a key of its own.
    static let listKeys: Set<KeyCode> = [
        .leftArrow, .rightArrow, .upArrow, .downArrow, .pageUp, .pageDown, .delete, .forwardDelete, .home, .end,
        .keypadEnter, .escape,
    ]

    /// Whether the user can give a row these keys. Command must be among them, so typing in the search field, on
    /// any keyboard layout, is never taken.
    /// `reserved` is passed when many keys are asked about at once, so the layout is read once.
    static func canBeChosen(_ keys: KeyCombination, reserved: Set<KeyCombination>? = nil) -> Bool {
        keys.modifiers.contains(.command) && !listKeys.contains(keys.key) && !(reserved ?? reservedKeys()).contains(keys)
    }

    /// The rows on offer by id, those in submenus included. Where two share an id, the first is kept.
    static func offered(_ actions: [ItemAction?]) -> [ActionID: ItemAction] {
        var found: [ActionID: ItemAction] = [:]
        // Reversed, so taking from the end visits rows in menu order, each submenu's rows right after it.
        var pending = Array(actions.compactMap(\.self).reversed())
        while let action = pending.popLast() {
            if let id = action.id, found[id] == nil {
                found[id] = action
            }
            pending.append(contentsOf: action.children.reversed())
        }
        return found
    }

    /// What Return runs: the first default on offer. Nil when none is, so Return does what Floe does. A submenu, such
    /// as Open With, runs nothing itself, so it is passed over, as Settings passes it over.
    static func primary(_ choices: KindActions, offered: [ActionID: ItemAction]) -> ItemAction? {
        choices.defaults.lazy.compactMap { offered[$0] }.first { $0.children.isEmpty }
    }

    /// The Actions menu after the Return row. When a default took Return, `own` is what Floe does, listed first;
    /// the default's own row is left out, being the Return row now. The rows follow the user's order, and hidden
    /// rows are left out.
    static func arranged(_ actions: [ItemAction?], own: ItemAction?, primaryID: ActionID?, choices: KindActions) -> [ItemAction?] {
        guard own != nil || choices != KindActions() else { return actions }
        // Rows left out go first, so a separator is only put between rows that are shown.
        let shown = actions.compactMap { row -> ItemAction?? in
            guard let row else { return .some(nil) }
            return kept(row, primaryID: primaryID, choices: choices).map { .some($0) }
        }
        // Floe's own Return is parted from the Return row above it; without it, the rows start as Floe has them.
        return tidied((own.map { [nil, $0] } ?? []) + ordered(shown, by: choices.order))
    }

    /// The rows in the user's order. A separator parts two rows next to each other that Floe's menu has in
    /// different groups, so with Floe's order the menu is Floe's. A submenu's rows keep Floe's order.
    static func ordered(_ rows: [ItemAction?], by order: [ActionID]) -> [ItemAction?] {
        guard !order.isEmpty else { return rows }
        var group = 0
        var grouped: [(row: ItemAction, group: Int)] = []
        for row in rows {
            if let row {
                grouped.append((row, group))
            } else {
                group += 1
            }
        }
        let sorted = ordered(grouped, by: order) { $0.row.id }
        // A separator at the start parts the rows from the Return row above them, so it stays.
        var result: [ItemAction?] = rows.first.map { $0 == nil } == true ? [nil] : []
        for (index, entry) in sorted.enumerated() {
            if index > 0, sorted[index - 1].group != entry.group {
                result.append(nil)
            }
            result.append(entry.row)
        }
        return result
    }

    /// Items in the user's order. One the order does not name, such as a script added since, stays after the item it
    /// follows in Floe's order, or first when it is first there.
    static func ordered<Item>(_ items: [Item], by order: [ActionID], id: (Item) -> ActionID?) -> [Item] {
        guard !order.isEmpty else { return items }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        var placed = -1
        var after = 0
        let keyed = items.map { item -> (item: Item, place: Int, after: Int) in
            if let place = id(item).flatMap({ rank[$0] }) {
                placed = place
                after = 0
            } else {
                after += 1
            }
            return (item, placed, after)
        }
        return keyed.sorted { ($0.place, $0.after) < ($1.place, $1.after) }.map(\.item)
    }

    /// One separator at most between groups, and none at the end. A separator at the start stays: it parts the
    /// rows from the Return row above them.
    static func tidied(_ rows: [ItemAction?]) -> [ItemAction?] {
        var result: [ItemAction?] = []
        for row in rows where row != nil || result.last.map({ $0 != nil }) ?? true {
            result.append(row)
        }
        while let last = result.last, last == nil {
            result.removeLast()
        }
        return result
    }

    /// A row with its hidden children left out; nil when the row itself is left out.
    private static func kept(_ row: ItemAction, primaryID: ActionID?, choices: KindActions) -> ItemAction? {
        if let id = row.id, id == primaryID || (id != .own && choices.hidden.contains(id)) {
            return nil
        }
        var row = row
        if !row.children.isEmpty {
            row.children = row.children.compactMap { kept($0, primaryID: primaryID, choices: choices) }
            if row.children.isEmpty {
                return nil
            }
        }
        return row
    }
}
