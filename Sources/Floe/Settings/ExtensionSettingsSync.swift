//
//  ExtensionSettingsSync.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Extension preferences as sync records. A record names only values that mean the same on every Mac:
/// passwords, files, folders and chosen apps are never in one.
final class ExtensionSettingsSync {
    /// The last record of each extension by name, and the ones another Mac sent that are not applied here yet.
    struct Held: Codable, Equatable {
        var records: [String: String] = [:]
        var pending: Set<String> = []
    }

    struct Storage {
        var load: () -> Held?
        var save: (Held) -> Void

        static func file(_ url: URL) -> Storage {
            Storage(
                load: { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Held.self, from: $0) } },
                save: { held in
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? JSONEncoder().encode(held).write(to: url, options: .atomic)
                }
            )
        }
    }

    /// What this needs of Floe, as closures so a test plays two Macs without a file or a scan.
    struct Access {
        /// The sub-switch. Off, nothing of this Mac's is read and nothing another Mac sent is written.
        var includes: () -> Bool
        /// The commands of the extensions installed here, whose manifests say which preferences exist.
        var commands: () -> [ExtensionCommand]
        var stored: (_ extensionName: String) -> [String: Any]
        /// Writes the named values over the stored ones, the way an edit in Settings does.
        var merge: (_ values: [String: Any], _ extensionName: String) -> Void
    }

    /// One record per extension and not per preference: iCloud's store takes 1,024 keys in all.
    static let prefix = "ext/"
    /// An allow list, so a kind added later stays on this Mac until someone decides it may leave.
    static let syncedTypes: Set<String> = ["textfield", "checkbox", "dropdown"]

    private let access: Access
    private let storage: Storage
    private(set) var held: Held

    init(access: Access, storage: Storage) {
        self.access = access
        self.storage = storage
        held = storage.load() ?? Held()
    }

    /// The preferences that may sync, by extension and then by the key each is stored under.
    static func fields(of commands: [ExtensionCommand]) -> [String: [String: FieldSpec]] {
        var result: [String: [String: FieldSpec]] = [:]
        for command in commands {
            // An extension with nothing to sync is still listed: it is installed, so nothing waits for it.
            var fields = result[command.extensionName] ?? [:]
            for field in command.extensionPreferences where syncedTypes.contains(field.type) {
                fields[PreferenceResolver.storageKey(field, commandName: nil)] = field
            }
            for field in command.commandPreferences where syncedTypes.contains(field.type) {
                fields[PreferenceResolver.storageKey(field, commandName: command.name)] = field
            }
            result[command.extensionName] = fields
        }
        return result
    }

    /// Whether a value is one the field can hold. A dropdown takes only an option this version of the extension has.
    static func accepts(_ value: Any, for field: FieldSpec) -> Bool {
        switch field.type {
        case "checkbox": value is Bool
        case "dropdown": (value as? String).map { text in field.options.isEmpty || field.options.contains { $0.value == text } } ?? false
        default: value is String
        }
    }

    static func syncable(_ values: [String: Any], fields: [String: FieldSpec]) -> [String: Any] {
        values.filter { entry in fields[entry.key].map { accepts(entry.value, for: $0) } ?? false }
    }

    private static func object(_ text: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    /// Every extension's record. One that is not installed here, or all of them while the switch is off,
    /// keep the record they had, so the engine sees no removal and no change.
    func records() -> [String: String] {
        if access.includes() {
            var next = held
            for (name, fields) in Self.fields(of: access.commands()) {
                var values = Self.syncable(access.stored(name), fields: fields)
                if next.pending.remove(name) != nil, let waiting = next.records[name].flatMap(Self.object) {
                    let incoming = Self.syncable(waiting, fields: fields)
                    if !incoming.isEmpty {
                        access.merge(incoming, name)
                        values.merge(incoming) { _, theirs in theirs }
                    }
                }
                if !values.isEmpty, let text = SettingsSync.text(values) {
                    next.records[name] = text
                }
            }
            keep(next)
        }
        return Dictionary(uniqueKeysWithValues: held.records.map { (Self.prefix + $0.key, $0.value) })
    }

    /// Takes in other Macs' records and answers with the ones that are not records. A removal elsewhere
    /// forgets the record and leaves this Mac's preferences as they are.
    func apply(_ changed: [String: String], removed: Set<String>) -> Set<String> {
        guard changed.keys.contains(where: { $0.hasPrefix(Self.prefix) }) || removed.contains(where: { $0.hasPrefix(Self.prefix) }) else { return [] }
        var next = held
        var refused: Set<String> = []
        let installed = access.includes() ? Self.fields(of: access.commands()) : [:]
        for (key, text) in changed where key.hasPrefix(Self.prefix) {
            let name = String(key.dropFirst(Self.prefix.count))
            guard !name.isEmpty, let values = Self.object(text) else {
                refused.insert(key)
                continue
            }
            next.records[name] = text
            if let fields = installed[name] {
                let incoming = Self.syncable(values, fields: fields)
                if !incoming.isEmpty {
                    access.merge(incoming, name)
                }
                next.pending.remove(name)
            } else {
                next.pending.insert(name)
            }
        }
        for key in removed where key.hasPrefix(Self.prefix) {
            let name = String(key.dropFirst(Self.prefix.count))
            next.records[name] = nil
            next.pending.remove(name)
        }
        keep(next)
        return refused
    }

    private func keep(_ next: Held) {
        guard next != held else { return }
        held = next
        storage.save(next)
    }
}

extension ExtensionSettingsSync.Access {
    /// The preferences as `PreferenceStore` keeps them, which is where a command reads them when it starts.
    static func stored(includes: @escaping () -> Bool, commands: @escaping () -> [ExtensionCommand]) -> Self {
        Self(includes: includes, commands: commands, stored: PreferenceStore.storedValues, merge: PreferenceStore.merge)
    }
}
