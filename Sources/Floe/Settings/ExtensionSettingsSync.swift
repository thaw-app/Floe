//
//  ExtensionSettingsSync.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Extension preferences as sync records. A record names only values that mean the same on every Mac:
/// passwords, files, folders and chosen apps are never in one, nor text fields that look like they hold a credential.
final class ExtensionSettingsSync {
    /// The last record of each extension by name, and the ones another Mac sent that are not applied here yet.
    struct Held: Codable, Equatable {
        var records: [String: String] = [:]
        var pending: Set<String> = []
        /// The synced keys this Mac held at its last pass, by extension, to tell a value cleared here from one it never
        /// had. Optional, so a file written before it was kept still loads.
        var sent: [String: Set<String>]?
    }

    struct Storage {
        var load: () -> Held?
        var save: (Held) -> Void

        static func file(_ url: URL) -> Storage {
            Storage(
                load: { JSONFile.read(Held.self, from: url) },
                save: { JSONFile.write($0, to: url) }
            )
        }
    }

    /// What this needs of Floe, as closures so a test plays two Macs without a file or a scan.
    struct Access {
        /// The sub-switch. Off, nothing of this Mac's is read and nothing another Mac sent is written.
        var includes: () -> Bool
        /// The commands of the extensions installed here, whose manifests say which preferences exist.
        var commands: () -> [ExtensionCommand]
        /// Nil when there is no file that could be read: nothing is known, so nothing is cleared.
        var stored: (_ extensionName: String) -> [String: Any]?
        /// Writes the named values over the stored ones, the way an edit in Settings does. A null removes its key.
        /// False when nothing was written.
        var merge: (_ values: [String: Any], _ extensionName: String) -> Bool
    }

    /// One record per extension and not per preference: iCloud's store takes 1,024 keys in all.
    static let prefix = "ext/"
    /// An allow list, so a kind added later stays on this Mac until someone decides it may leave.
    static let syncedTypes: Set<String> = ["textfield", "checkbox", "dropdown"]
    /// Words in a text field's name or title that say it holds a credential. Such a field stays on this Mac:
    /// extensions often ask for a token in a plain text field rather than a password one.
    static let secretWords: Set<String> = [
        "token", "tokens", "key", "keys", "apikey", "secret", "secrets", "password", "passwords", "passwd", "pwd",
        "passphrase", "auth", "oauth", "authorization", "credential", "credentials", "bearer", "cookie", "cookies",
    ]

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
            for field in command.extensionPreferences where syncedTypes.contains(field.type) && !looksSecret(field) {
                fields[PreferenceResolver.storageKey(field, commandName: nil)] = field
            }
            for field in command.commandPreferences where syncedTypes.contains(field.type) && !looksSecret(field) {
                fields[PreferenceResolver.storageKey(field, commandName: command.name)] = field
            }
            result[command.extensionName] = fields
        }
        return result
    }

    /// The words of a name or title: split at spaces, punctuation, digits and camel case, lowercased, so
    /// "keyboard" is one word and "apiKey" is two.
    static func words(_ text: String) -> [String] {
        let letters = Array(text)
        var words: [String] = []
        var word = ""
        for (index, letter) in letters.enumerated() {
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            // The last capital of a run that goes on in lower case starts a word, so "APIKey" is "API" and "Key".
            let startsWord = letter.isUppercase && word.last.map { $0.isLowercase || ($0.isUppercase && next?.isLowercase == true) } == true
            if !letter.isLetter || startsWord, !word.isEmpty {
                words.append(word.lowercased())
                word = ""
            }
            if letter.isLetter {
                word.append(letter)
            }
        }
        if !word.isEmpty {
            words.append(word.lowercased())
        }
        return words
    }

    static func looksSecret(_ text: String) -> Bool {
        !secretWords.isDisjoint(with: words(text))
    }

    static func looksSecret(_ field: FieldSpec) -> Bool {
        field.type == "textfield" && (looksSecret(field.name) || looksSecret(field.title))
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

    /// What a record asks to write here: its syncable values, and a null for each field it says was cleared.
    static func incoming(_ record: [String: Any], fields: [String: FieldSpec]) -> [String: Any] {
        syncable(record, fields: fields).merging(record.filter { fields[$0.key] != nil && $0.value is NSNull }) { value, _ in value }
    }

    private static func object(_ text: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    /// Every extension's record. One that is not installed here, or all of them while the switch is off,
    /// keep the record they had, so the engine sees no removal and no change.
    func records() -> [String: String] {
        if access.includes() {
            var next = held
            let installed = Self.fields(of: access.commands())
            // An older Floe may have sent a credential. With no manifest here to read a title from, the key's name decides.
            for (name, text) in next.records where installed[name] == nil {
                if let kept = Self.withoutSecrets(text) {
                    next.records[name] = kept
                }
            }
            for (name, fields) in installed {
                record(name, fields: fields, into: &next)
            }
            keep(next)
        }
        return Dictionary(uniqueKeysWithValues: held.records.map { (Self.prefix + $0.key, $0.value) })
    }

    /// The record without keys named like a credential, or nil when it has none.
    private static func withoutSecrets(_ text: String) -> String? {
        guard let values = object(text) else { return nil }
        let kept = values.filter { !looksSecret(String($0.key.split(separator: "/").last ?? "")) }
        return kept.count < values.count ? SettingsSync.text(kept) : nil
    }

    /// Applies a record waiting for this extension, then rebuilds its record from what is stored here.
    private func record(_ name: String, fields: [String: FieldSpec], into next: inout Held) {
        let stored = access.stored(name)
        var values = Self.syncable(stored ?? [:], fields: fields)
        if next.pending.remove(name) != nil, let waiting = next.records[name].flatMap(Self.object) {
            let incoming = Self.incoming(waiting, fields: fields)
            if !incoming.isEmpty {
                guard access.merge(incoming, name) else {
                    // Tried again on the next pass, and the record stays as it came.
                    next.pending.insert(name)
                    return
                }
                // The nulls stay in the record, so a clearing this Mac passes on is not lost when nothing is stored here.
                values = values.merging(incoming) { _, theirs in theirs }
            }
        }
        guard stored != nil else {
            if !values.isEmpty, let text = SettingsSync.text(values) {
                next.records[name] = text
            }
            return
        }
        let here = Set(values.filter { !($0.value is NSNull) }.keys)
        // The whole record wins, so a removal is said inside it as a null. A key left out is not a removal:
        // an older version of the extension or of Floe never clears what it does not know.
        let previous = next.records[name].flatMap(Self.object) ?? [:]
        let cleared = (next.sent?[name] ?? []).union(previous.filter { $0.value is NSNull }.keys)
        for key in cleared where fields[key] != nil && !here.contains(key) {
            values[key] = NSNull()
        }
        if !values.isEmpty || next.records[name] != nil, let text = SettingsSync.text(values) {
            next.records[name] = text
        }
        var sent = next.sent ?? [:]
        sent[name] = here
        next.sent = sent
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
                let incoming = Self.incoming(values, fields: fields)
                // A record that could not be written here waits, as for an extension not installed yet.
                if incoming.isEmpty || access.merge(incoming, name) {
                    next.pending.remove(name)
                } else {
                    next.pending.insert(name)
                }
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
        Self(
            includes: includes,
            commands: commands,
            stored: {
                guard case let .values(values) = PreferenceStore.storedFile($0) else { return nil }
                return values
            },
            merge: { PreferenceStore.merge($0, extensionName: $1) }
        )
    }
}
