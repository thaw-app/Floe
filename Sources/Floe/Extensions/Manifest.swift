//
//  Manifest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A preference or argument declared in an extension manifest, as an editable field.
nonisolated struct FieldSpec: Identifiable, Decodable, Sendable {
    let name: String
    let title: String
    let detail: String?
    /// Raycast's type names: textfield, password, checkbox, dropdown, appPicker, file, directory (preferences);
    /// text, password, dropdown (arguments).
    let type: String
    let required: Bool
    let placeholder: String?
    /// Checkbox label.
    let label: String?
    let options: [(title: String, value: String)]

    /// The manifest default, kept as one of the four scalars manifests can declare, so the field
    /// stays transferable across actors despite the untyped `defaultValue` interface below.
    private enum DefaultValue: Sendable {
        case bool(Bool)
        case string(String)
        case int(Int)
        case double(Double)
    }

    private let storedDefault: DefaultValue?

    var id: String {
        name
    }

    var isSecret: Bool {
        type == "password"
    }

    /// A default is a string or, for a checkbox, a boolean; it stays untyped because it is passed on as JSON.
    var defaultValue: Any? {
        switch storedDefault {
        case let .bool(value): value
        case let .double(value): value
        case let .int(value): value
        case let .string(value): value
        case nil: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, type, required, placeholder, label
        case detail = "description"
        case options = "data"
        case defaultValue = "default"
    }

    private struct Option: Decodable {
        let title: String?
        let value: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "textfield"
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? (type == "checkbox" ? "" : placeholder ?? name)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.options = try (container.decodeIfPresent(Lossy<Option>.self, forKey: .options)?.elements ?? [])
            .map { ($0.title ?? $0.value, $0.value) }
        // A default given per platform is an object keyed by platform, and the Mac's value is the one taken.
        storedDefault = Self.scalar(in: container, forKey: .defaultValue)
            ?? (try? container.nestedContainer(keyedBy: PlatformKeys.self, forKey: .defaultValue)).flatMap { Self.scalar(in: $0, forKey: .macOS) }
    }

    private enum PlatformKeys: String, CodingKey {
        case macOS
    }

    /// A default is a string or, for a checkbox, a boolean; the scalar order here is the
    /// precedence, so a whole number stays an Int and only genuine fractions become Double.
    private static func scalar<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) -> DefaultValue? {
        (try? container.decode(Bool.self, forKey: key)).map(DefaultValue.bool)
            ?? (try? container.decode(String.self, forKey: key)).map(DefaultValue.string)
            ?? (try? container.decode(Int.self, forKey: key)).map(DefaultValue.int)
            ?? (try? container.decode(Double.self, forKey: key)).map(DefaultValue.double)
    }
}

/// An array that keeps the elements that decode and drops the rest: one bad entry must not hide the manifest.
nonisolated struct Lossy<Element: Decodable>: Decodable {
    private struct Skipped: Decodable {}

    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode leaves the container where it was.
                _ = try container.decode(Skipped.self)
            }
        }
        self.elements = elements
    }
}

nonisolated struct ExtensionCommand: Identifiable, Sendable {
    enum Source: Sendable { case local, raycast }

    let extensionDir: URL
    let extensionName: String
    let extensionTitle: String
    let source: Source
    let name: String
    let title: String
    let mode: String
    let interval: TimeInterval?
    let icon: String?
    let arguments: [FieldSpec]
    let extensionPreferences: [FieldSpec]
    let commandPreferences: [FieldSpec]
    /// The words the manifest lists for the extension and for this command, which the root search also answers to.
    var keywords: [String] = []
    /// The manifest's disabledByDefault: the command stays off until the user switches it on in Settings.
    var isDisabledByDefault = false
    /// Who the extension's links name: the manifest's owner, or else its author. Nil when it has neither.
    var owner: String?
    /// The manifest's subtitle, which the command can replace while it runs (see CommandSubtitles).
    var subtitle: String?
    /// The extension's own icon and description, for its page in Settings; a command's icon may be its own.
    var extensionIcon: String?
    var extensionDescription: String?

    var id: String {
        "\(extensionName)/\(name)"
    }

    var assetsPath: String {
        extensionDir.appendingPathComponent("assets").path
    }

    var preferences: [FieldSpec] {
        extensionPreferences + commandPreferences
    }

    /// Whether a manifest's name can name an extension. It becomes a folder name and the first part of Keychain accounts,
    /// so it has no slash, is not "." or "..", and stays clear of the "floe." names Floe's own secrets use.
    static func isUsableName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.lowercased().hasPrefix("floe.")
    }

    private struct Manifest: Decodable {
        let name: String
        let owner: String?
        let author: ManifestAuthor?
        let title: String?
        let description: String?
        let icon: String?
        let keywords: Lossy<String>?
        let platforms: Lossy<String>?
        let preferences: Lossy<FieldSpec>?
        let commands: Lossy<ManifestCommand>
    }

    private struct ManifestCommand: Decodable {
        let name: String
        let title: String?
        let subtitle: String?
        let mode: String?
        let interval: String?
        let disabledByDefault: Bool?
        let icon: String?
        let keywords: Lossy<String>?
        let platforms: Lossy<String>?
        let arguments: Lossy<FieldSpec>?
        let preferences: Lossy<FieldSpec>?
    }

    /// Parses Raycast `interval` strings (`90s`, `10m`, `1h`, `1d`); clamps to at least 10 seconds.
    static func parseInterval(_ raw: String?) -> TimeInterval? {
        guard let raw, !raw.isEmpty else { return nil }
        let multipliers: [Character: Double] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
        guard let unit = raw.last, let factor = multipliers[unit],
              let value = Double(raw.dropLast()), value.isFinite else { return nil }
        return max(value * factor, 10)
    }

    /// Whether a manifest's platforms list, of an extension or of a command, has the Mac in it. No list means every platform.
    static func runsOnMac(_ platforms: [String]?) -> Bool {
        platforms?.contains("macOS") ?? true
    }

    /// The commands a package.json declares that Floe can run: view, no-view and menu-bar, for the Mac.
    static func commands(inManifest data: Data, folder: URL, source: Source) -> [ExtensionCommand] {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data), isUsableName(manifest.name), runsOnMac(manifest.platforms?.elements) else { return [] }
        let custom = CustomIcon.path(for: manifest.name)
        return manifest.commands.elements.compactMap { command in
            let mode = command.mode ?? "view"
            guard mode == "view" || mode == "no-view" || mode == "menu-bar", runsOnMac(command.platforms?.elements) else { return nil }
            return ExtensionCommand(
                extensionDir: folder,
                extensionName: manifest.name,
                extensionTitle: manifest.title ?? manifest.name,
                source: source,
                name: command.name,
                title: command.title ?? command.name,
                mode: mode,
                interval: parseInterval(command.interval),
                icon: custom ?? command.icon ?? manifest.icon,
                arguments: command.arguments?.elements ?? [],
                extensionPreferences: manifest.preferences?.elements ?? [],
                commandPreferences: command.preferences?.elements ?? [],
                keywords: (command.keywords?.elements ?? []) + (manifest.keywords?.elements ?? []),
                isDisabledByDefault: command.disabledByDefault ?? false,
                owner: manifest.owner ?? manifest.author?.name,
                subtitle: command.subtitle.flatMap { $0.isEmpty ? nil : $0 },
                extensionIcon: custom ?? manifest.icon,
                extensionDescription: manifest.description.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }
}

/// A name, or an object with one; anything else is no author rather than a manifest that cannot be read.
private nonisolated struct ManifestAuthor: Decodable {
    let name: String?

    private enum Keys: String, CodingKey { case name }

    init(from decoder: Decoder) throws {
        name = (try? decoder.singleValueContainer().decode(String.self))
            ?? (try? decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .name))
    }
}

nonisolated struct AppEntry: Sendable {
    let name: String
    let url: URL
    /// What tells this app from another of its name: the folder it is in, or its file's name. Nil for a name of its own.
    var origin: String?
}
