//
//  Preferences.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Converts between the text a field editor holds and the typed values a command receives.
enum FieldValues {
    /// Checkboxes edit as "true" or "false"; everything else as its text.
    static func text(from value: Any) -> String {
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        return value as? String ?? "\(value)"
    }

    /// What an editor starts with: the stored or default value, else a dropdown's first option, else empty.
    static func initialText(for field: FieldSpec, stored: Any?) -> String {
        (stored ?? field.defaultValue).map(text(from:))
            ?? (field.type == "dropdown" ? field.options.first?.value : nil)
            ?? ""
    }

    static func typed(_ texts: [String: String], fields: [FieldSpec]) -> [String: Any] {
        fields.reduce(into: [String: Any]()) { result, field in
            let text = texts[field.name] ?? ""
            result[field.name] = field.type == "checkbox" ? (text == "true") : text
        }
    }

    /// Required fields still empty. A checkbox always has a value, so it never counts.
    static func missing(_ fields: [FieldSpec], texts: [String: String]) -> [FieldSpec] {
        fields.filter { $0.required && $0.type != "checkbox" && (texts[$0.name] ?? "").isEmpty }
    }
}

/// A checkbox has two texts in Raycast: a `label` beside the box, and a `title` at the side that often heads
/// several checkboxes, of which only the first carries it.
nonisolated enum CheckboxText {
    /// The text beside the box, and the heading over it when the title is not already that text.
    /// `name` is the manifest's internal key, used only when it gave neither a label nor a title.
    static func parts(title: String?, label: String?, name: String = "") -> (heading: String?, text: String) {
        let title = title.flatMap { $0.isEmpty ? nil : $0 }
        guard let label, !label.isEmpty else { return (nil, title ?? name) }
        return (title, label)
    }
}

extension FieldSpec {
    var checkbox: (heading: String?, text: String) {
        CheckboxText.parts(title: title, label: label, name: name)
    }

    /// What the field is called wherever it is named: a checkbox by the text beside it, the rest by their title.
    var displayTitle: String {
        type == "checkbox" ? checkbox.text : title
    }
}

/// Works out the values `getPreferenceValues()` returns, given where each value is kept.
enum PreferenceResolver {
    /// Command preferences are stored under "command/name" so two commands can reuse a name.
    static func storageKey(_ field: FieldSpec, commandName: String?) -> String {
        commandName.map { "\($0)/\(field.name)" } ?? field.name
    }

    /// Stored values first, then manifest defaults; an unset checkbox is false.
    /// `stored` holds the plain values by storage key and `secret` looks up password fields.
    static func resolve(
        extensionFields: [FieldSpec],
        commandFields: [FieldSpec],
        commandName: String,
        stored: [String: Any],
        secret: (String) -> String?
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        let scoped = extensionFields.map { ($0, String?.none) } + commandFields.map { ($0, String?.some(commandName)) }
        for (field, scope) in scoped {
            let key = storageKey(field, commandName: scope)
            if let value: Any = field.isSecret ? secret(key) : stored[key] {
                result[field.name] = value
            } else if let fallback = field.defaultValue {
                result[field.name] = fallback
            } else if field.type == "checkbox" {
                result[field.name] = false
            }
        }
        return result
    }

    static func missingRequired(_ fields: [FieldSpec], values: [String: Any]) -> [FieldSpec] {
        fields.filter { field in
            guard field.required else { return false }
            if let text = values[field.name] as? String {
                return text.isEmpty
            }
            return values[field.name] == nil
        }
    }
}

/// `appPicker` preferences: edited and stored as the app's path, handed to the command as
/// `{ name, path, bundleId }`. A manifest default may name the app by bundle id, name or path.
enum AppPickerValue {
    struct App: Equatable {
        let name: String
        let path: String
        let bundleId: String?

        var object: [String: String] {
            var object = ["name": name, "path": path]
            object["bundleId"] = bundleId
            return object
        }
    }

    /// The app a stored or default value names, matched by path, then bundle id, then name.
    static func match(_ value: String, in apps: [App]) -> App? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let path = (trimmed as NSString).expandingTildeInPath
        return apps.first { $0.path == path }
            ?? apps.first { $0.bundleId?.caseInsensitiveCompare(trimmed) == .orderedSame }
            ?? apps.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            ?? apps.first { $0.name.caseInsensitiveCompare((trimmed as NSString).deletingPathExtension) == .orderedSame }
    }

    /// Replaces each app picker's text with the app object, and drops ones that name no installed app,
    /// so a required picker without an app counts as missing.
    static func resolve(_ values: [String: Any], fields: [FieldSpec], apps: () -> [App]) -> [String: Any] {
        let pickers = fields.filter { $0.type == "appPicker" }
        guard !pickers.isEmpty else { return values }
        var result = values
        let installed = apps()
        for field in pickers {
            if let text = values[field.name] as? String, let app = match(text, in: installed) {
                result[field.name] = app.object
            } else if !(values[field.name] is [String: Any]) {
                result[field.name] = nil
            }
        }
        return result
    }
}
