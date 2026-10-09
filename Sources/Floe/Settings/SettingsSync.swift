//
//  SettingsSync.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Which of Floe's stored settings sync between Macs, and how each becomes records. A setting in neither
/// list here is not synced, and `SettingsSyncTests` fails until it is put in one.
enum SettingsSync {
    /// How one stored setting is cut into records.
    enum Shape {
        /// One record holds the whole value.
        case whole
        /// A dictionary with one record per entry, so two Macs changing different entries both keep theirs.
        /// With `only`, the other entries stay on this Mac.
        case entries(only: Set<String>?)
        /// A list in a chosen order: one record per member, and one more for the order.
        case ordered
    }

    struct Field {
        let name: String
        let shape: Shape
        /// Whether JSON is a value this setting can hold. A record that is not one is refused, not stored.
        let accepts: (Data) -> Bool
    }

    private static func field(_ name: String, _ type: (some Decodable).Type, _ shape: Shape = .whole) -> Field {
        Field(name: name, shape: shape) { (try? JSONDecoder().decode(type, from: $0)) != nil }
    }

    static let synced: [Field] = [
        field("toggleHotkey", KeyCombination.self),
        field("commandHotkeys", KeyCombination.self, .entries(only: nil)),
        field("aliases", String.self, .entries(only: nil)),
        field("favorites", String.self, .ordered),
        field("hiddenResults", String.self, .entries(only: nil)),
        field("emojiSkinTone", EmojiSkinTone.self),
        field("popToRootDelay", Int.self),
        field("rememberMenuBarQuery", Bool.self),
        field("notesApp", NotesApp.self),
        field("notesURLTemplate", String.self),
        field("launcherTintIsDynamic", Bool.self),
        field("launcherTintLight", LauncherTint.self),
        field("launcherTintDark", LauncherTint.self),
        field("launcherBorder", LauncherBorder.self),
        field("launcherShowsBorder", Bool.self),
        field("launcherShowsShadow", Bool.self),
        field("launcherGlass", LauncherGlass.self),
        field("launcherLayout", LauncherLayout.self),
        field("searchFieldShape", SearchFieldShape.self),
        field("separatesSearchField", Bool.self),
        // Of the shell settings only the prefix: whether commands run at all is decided on each Mac.
        field("shell", CommandPrefix.self, .entries(only: ["prefix"])),
    ]

    /// The settings that never leave this Mac, each with why.
    static let thisMacOnly: [String: String] = [
        "notesFolder": "a path on this Mac",
        "terminalApp": "holds the app's path on this Mac",
        "editorApp": "holds the app's path on this Mac",
        "browserApp": "holds the app's path on this Mac",
        "clipboardApp": "holds the app's path on this Mac",
        "clipboardHandler": "goes with the clipboard app chosen on this Mac",
        "clipboardURL": "goes with the clipboard app chosen on this Mac",
        "clipboardHistoryEnabled": "whether this Mac records what is copied",
        "includeRaycastExtensions": "reads a folder on this Mac and loads the code in it",
        "disabledExtensions": "switching an extension back on runs its code, which is decided on each Mac",
        "disabledCommands": "switching a command back on runs its code, which is decided on each Mac",
        "menuBarCommands": "the commands running in this Mac's menu bar",
        "menuBarItemNames": "keyed by where an item sits in this Mac's menu bar",
        "searchSources": "each source was switched on here after macOS asked for access",
        "indexesFileNames": "a permission given on this Mac",
        "focusShortcut": "names a Shortcut that exists on this Mac",
        "fetchesExchangeRates": "consent to a download, given on this Mac",
        "lentSignIns": "sign-ins lent to extensions on this Mac",
        "aiSource": "what answers depends on what is installed and signed in here",
        "aiBaseURL": "goes with a key in this Mac's Keychain",
        "aiModel": "goes with the AI source of this Mac",
        "aiTool": "a command line tool installed on this Mac",
        "aiToolModels": "goes with the tools installed on this Mac",
        "aiSourceByExtension": "goes with the AI source of this Mac",
        "aiOnThisMacOnly": "a promise about this Mac, never loosened from elsewhere",
        "remembersSearches": "whether this Mac keeps a history, and off forgets it here",
        "keepsReceipts": "whether this Mac keeps receipts, and off forgets them here",
        "recordsExtensionAccess": "whether this Mac keeps the access record, and off forgets it here",
        "followsThawAppearance": "needs Thaw running on this Mac and asks it",
        "showInDock": "how the app sits on this Mac",
        "hasSeenOnboarding": "the welcome is shown once on each Mac",
        "diagnosticLogging": "a log file on this Mac",
        "launcherTint": "read once from an older version's settings and never saved",
        "syncsWithICloud": "the sync switch itself, so each Mac joins by choice",
    ]

    static let prefix = "s."
    private static let orderSuffix = "#order"

    static func text(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func value(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    }

    /// The records for the stored settings, given as the object their JSON reads to.
    static func records(of settings: [String: Any]) -> [String: String] {
        var records: [String: String] = [:]
        for field in synced {
            guard let stored = settings[field.name] else { continue }
            let key = prefix + field.name
            switch field.shape {
            case .whole:
                records[key] = text(stored)
            case let .entries(only):
                for (name, entry) in stored as? [String: Any] ?? [:] where only?.contains(name) != false {
                    records["\(key)/\(name)"] = text(entry)
                }
            case .ordered:
                let members = stored as? [String] ?? []
                for member in members {
                    records["\(key)/\(member)"] = "true"
                }
                records[key + orderSuffix] = text(members)
            }
        }
        return records
    }

    private static func target(of key: String) -> (field: Field, entry: String?, isOrder: Bool)? {
        guard key.hasPrefix(prefix) else { return nil }
        let rest = key.dropFirst(prefix.count)
        let name = rest.prefix { $0 != "/" && $0 != "#" }
        guard let field = synced.first(where: { $0.name == name }) else { return nil }
        let tail = rest.dropFirst(name.count)
        if tail.isEmpty {
            return (field, nil, false)
        }
        return tail == orderSuffix ? (field, nil, true) : (field, String(tail.dropFirst()), false)
    }

    /// Whether a record is one this version can store: its shape matches the setting, and its value reads.
    private static func isAcceptable(_ text: String, for target: (field: Field, entry: String?, isOrder: Bool)) -> Bool {
        let data = Data(text.utf8)
        switch target.field.shape {
        case .whole:
            return target.entry == nil && !target.isOrder && target.field.accepts(data)
        case let .entries(only):
            guard let entry = target.entry, !target.isOrder else { return false }
            return only?.contains(entry) != false && target.field.accepts(data)
        case .ordered:
            if target.isOrder {
                return (try? JSONDecoder().decode([String].self, from: data)) != nil
            }
            return target.entry != nil && text == "true"
        }
    }

    /// The stored settings with another Mac's records taken in, and the keys that were refused.
    /// A key of a setting this version does not know is left alone, and is not a refusal.
    static func applying(_ changed: [String: String], removed: Set<String>, to settings: [String: Any]) -> (settings: [String: Any], refused: Set<String>) {
        var settings = settings
        var refused: Set<String> = []
        var orders: [String: [String]] = [:]
        for (key, text) in changed {
            guard let target = target(of: key) else { continue }
            guard isAcceptable(text, for: target), let value = value(text) else {
                refused.insert(key)
                continue
            }
            let name = target.field.name
            if target.isOrder {
                orders[name] = value as? [String]
            } else if let entry = target.entry {
                set(.some(value), entry: entry, of: target.field, in: &settings)
            } else {
                settings[name] = value
            }
        }
        for key in removed {
            guard let target = target(of: key), !target.isOrder else { continue }
            if let entry = target.entry {
                set(nil, entry: entry, of: target.field, in: &settings)
            } else {
                settings[target.field.name] = nil
            }
        }
        for (name, order) in orders {
            settings[name] = OrderedSync.arranged(settings[name] as? [String] ?? [], by: order)
        }
        return (settings, refused)
    }

    private static func set(_ value: Any?, entry: String, of field: Field, in settings: inout [String: Any]) {
        if case .ordered = field.shape {
            var members = settings[field.name] as? [String] ?? []
            members.removeAll { $0 == entry }
            if value != nil {
                members.append(entry)
            }
            settings[field.name] = members
        } else {
            var entries = settings[field.name] as? [String: Any] ?? [:]
            entries[entry] = value
            settings[field.name] = entries
        }
    }
}

/// A list whose members and whose order travel as separate records.
nonisolated enum OrderedSync {
    /// The members in the order given, then those the order does not name, as they stood.
    /// The order may name members that are gone; it never adds or removes one.
    static func arranged<Member: Hashable>(_ members: [Member], by order: [Member]) -> [Member] {
        let held = Set(members)
        var seen: Set<Member> = []
        let named = order.filter { held.contains($0) && seen.insert($0).inserted }
        return named + members.filter { seen.insert($0).inserted }
    }
}

/// A list of items as records: one per item under its id, and one for the order they are listed in.
struct ItemSync<Item> {
    let prefix: String
    let id: (Item) -> String
    let encode: (Item) -> String?
    let decode: (String) -> Item?

    private var orderKey: String {
        prefix + "#order"
    }

    func records(of items: [Item]) -> [String: String] {
        var records: [String: String] = [:]
        for item in items {
            records["\(prefix)/\(id(item))"] = encode(item)
        }
        records[orderKey] = SettingsSync.text(items.map(id))
        return records
    }

    /// The items with another Mac's records taken in, and the keys that were refused. Other prefixes are not looked at.
    func applying(_ changed: [String: String], removed: Set<String>, to items: [Item]) -> (items: [Item], refused: Set<String>) {
        var items = items
        var refused: Set<String> = []
        var order: [String]?
        for (key, text) in changed where key.hasPrefix(prefix + "/") || key == orderKey {
            if key == orderKey {
                order = try? JSONDecoder().decode([String].self, from: Data(text.utf8))
                if order == nil {
                    refused.insert(key)
                }
            } else if let item = decode(text), key == "\(prefix)/\(id(item))" {
                if let index = items.firstIndex(where: { id($0) == id(item) }) {
                    items[index] = item
                } else {
                    items.append(item)
                }
            } else {
                refused.insert(key)
            }
        }
        let gone = Set(removed.filter { $0.hasPrefix(prefix + "/") }.map { String($0.dropFirst(prefix.count + 1)) })
        items.removeAll { gone.contains(id($0)) }
        if let order {
            let byID = Dictionary(items.map { (id($0), $0) }) { first, _ in first }
            items = OrderedSync.arranged(items.map(id), by: order).compactMap { byID[$0] }
        }
        return (items, refused)
    }
}

extension ItemSync {
    private static func text(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static var snippets: ItemSync<Snippet> {
        ItemSync<Snippet>(prefix: "snip", id: \.id.uuidString, encode: { ItemSync<Snippet>.text($0) }, decode: { try? JSONDecoder().decode(Snippet.self, from: Data($0.utf8)) })
    }

    static var quicklinks: ItemSync<Quicklink> {
        ItemSync<Quicklink>(prefix: "ql", id: \.id.uuidString, encode: { ItemSync<Quicklink>.text($0) }, decode: { try? JSONDecoder().decode(Quicklink.self, from: Data($0.utf8)) })
    }
}
