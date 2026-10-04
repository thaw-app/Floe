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
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? placeholder ?? name
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "textfield"
        self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.options = try (container.decodeIfPresent(Lossy<Option>.self, forKey: .options)?.elements ?? [])
            .map { ($0.title ?? $0.value, $0.value) }
        // A default is a string or, for a checkbox, a boolean; the scalar order here is the
        // precedence, so a whole number stays an Int and only genuine fractions become Double.
        storedDefault = (try? container.decode(Bool.self, forKey: .defaultValue)).map(DefaultValue.bool)
            ?? (try? container.decode(String.self, forKey: .defaultValue)).map(DefaultValue.string)
            ?? (try? container.decode(Int.self, forKey: .defaultValue)).map(DefaultValue.int)
            ?? (try? container.decode(Double.self, forKey: .defaultValue)).map(DefaultValue.double)
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

    var id: String {
        "\(extensionName)/\(name)"
    }

    var assetsPath: String {
        extensionDir.appendingPathComponent("assets").path
    }

    var preferences: [FieldSpec] {
        extensionPreferences + commandPreferences
    }

    private struct Manifest: Decodable {
        let name: String
        let title: String?
        let icon: String?
        let preferences: Lossy<FieldSpec>?
        let commands: Lossy<ManifestCommand>
    }

    private struct ManifestCommand: Decodable {
        let name: String
        let title: String?
        let mode: String?
        let interval: String?
        let icon: String?
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

    /// The commands a package.json declares that Floe can run: view, no-view and menu-bar.
    static func commands(inManifest data: Data, folder: URL, source: Source) -> [ExtensionCommand] {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.commands.elements.compactMap { command in
            let mode = command.mode ?? "view"
            guard mode == "view" || mode == "no-view" || mode == "menu-bar" else { return nil }
            return ExtensionCommand(
                extensionDir: folder,
                extensionName: manifest.name,
                extensionTitle: manifest.title ?? manifest.name,
                source: source,
                name: command.name,
                title: command.title ?? command.name,
                mode: mode,
                interval: parseInterval(command.interval),
                icon: command.icon ?? manifest.icon,
                arguments: command.arguments?.elements ?? [],
                extensionPreferences: manifest.preferences?.elements ?? [],
                commandPreferences: command.preferences?.elements ?? []
            )
        }
    }
}

nonisolated struct AppEntry: Sendable {
    let name: String
    let url: URL
}

struct RootResult: Identifiable {
    let item: RootItem
    /// Shown above the first result of a run with the same title; only set when the query is empty.
    let section: String?
    var id: String {
        item.id
    }
}

enum RootItem: Identifiable {
    case app(AppEntry)
    case command(ExtensionCommand)
    case script(ScriptCommand)
    case menuBarSearch
    case emojiSearch
    case clipboardHistory
    /// Clipboard History while another app keeps the history: the same command, opened there.
    case clipboardApp(ClipboardDestination)
    case fileSearch
    case searchFiles(String)
    case settings
    case calculator(expression: String, result: String, error: String? = nil, attributedResult: AttributedString? = nil)
    case system(SystemCommand)
    case settingsPane(SystemSettingsPane)
    /// Something Thaw does when asked through its `thaw://` links.
    case thaw(ThawAction)
    /// The Finder selection, opened in the app a role stands for.
    case finderSelection(AppRole, app: ResolvedApp)
    /// A note for the user's notes app; `text` is what was typed after the action's keyword.
    case note(NoteAction, text: String)
    case event(CalendarEvent)
    case snippet(Snippet)
    case emoji(EmojiResult)
    /// A quicklink matched against the query: `queryText` is the text put into the URL,
    /// and `fallback`/`keywordSearch` rows read as Search … for "…" instead of the link's name.
    case quicklink(Quicklink, queryText: String, fallback: Bool, keywordSearch: Bool)
    /// A scope's rows: a file Spotlight found, a clipboard entry, a menu bar item under the name it is shown by.
    case file(FileResult)
    /// An open browser tab, or the row that stands in for a browser Floe may not ask (see BrowserTabs.swift).
    case browserTab(BrowserTabRow)
    case clipboardEntry(ClipboardEntry)
    case menuBarItem(MenuBarExtra, name: String)
    /// Stands in for the menu bar items until Floe may read them.
    case menuBarAccess
    /// A question for the chosen AI source. Its id leaves the question out, so nothing stores it.
    case askAI(String)
    case webAddress(WebAddress)
    /// A host of the SSH configuration, with the terminal it opens in.
    case sshHost(SSHHost, terminal: ResolvedApp?)
    /// A shortcut made in Apple's Shortcuts app; Return runs it there.
    case shortcut(AppleShortcut)

    static let menuBarSearchKey = "builtin:menubar-search"
    static let emojiSearchKey = "builtin:emoji-search"
    static let clipboardHistoryKey = "builtin:clipboard-history"
    static let fileSearchKey = "builtin:file-search"

    var id: String {
        switch self {
        case let .app(app): "app:\(app.url.path)"
        case let .command(command): "command:\(command.id)"
        case let .script(script): "script:\(script.file.lastPathComponent)"
        case .menuBarSearch: Self.menuBarSearchKey
        case .emojiSearch: Self.emojiSearchKey
        case .clipboardHistory, .clipboardApp: Self.clipboardHistoryKey
        case .fileSearch: Self.fileSearchKey
        case let .searchFiles(query): "files-for:\(query)"
        case .settings: "settings"
        case .calculator: "calculator"
        case let .system(command): "system:\(command.rawValue)"
        case let .settingsPane(pane): "settings-pane:\(pane.identifier)"
        case let .note(action, _): "note:\(action.rawValue)"
        case let .thaw(action): "thaw:\(action.rawValue)"
        case let .finderSelection(role, _): "finder-selection:\(role.rawValue)"
        case let .event(event): "event:\(event.identifier)"
        case let .snippet(snippet): "snippet:\(snippet.id.uuidString)"
        case let .emoji(entry): entry.id
        case let .quicklink(link, _, fallback, _):
            (fallback ? "quicklink-fallback:" : "quicklink:") + link.id.uuidString
        case let .file(file): "file:\(file.id)"
        case let .browserTab(row): row.id
        case let .clipboardEntry(entry): "clipboard-entry:\(entry.id.uuidString)"
        case let .menuBarItem(extra, _): "menubar-item:\(extra.id)"
        case .menuBarAccess: "menubar-access"
        case .askAI: "ask-ai"
        case .webAddress: "web-address"
        case let .sshHost(host, _): host.id
        case let .shortcut(shortcut): shortcut.id
        }
    }

    var title: String {
        switch self {
        case let .app(app): app.name
        case let .command(command): command.title
        case let .script(script): script.title
        case .menuBarSearch: String(localized: "Search Menu Bar Items", bundle: .floe)
        case .emojiSearch: String(localized: "Search Emoji & Symbols", bundle: .floe)
        case .clipboardHistory, .clipboardApp: String(localized: "Clipboard History", bundle: .floe)
        case .fileSearch: String(localized: "Search Files", bundle: .floe)
        case let .searchFiles(query): String(localized: "Search Files for \"\(query)\"", bundle: .floe, comment: "The placeholder is what the user typed.")
        case .settings: String(localized: "Floe Settings", bundle: .floe)
        case .calculator(_, let result, let error, _):
            error ?? (result.isEmpty ? String(localized: "Calculator", bundle: .floe) : result)
        case let .system(command): command.title
        case let .settingsPane(pane): pane.title
        case let .note(action, text): action.title(text: text)
        case let .thaw(action): action.title
        case let .finderSelection(_, app): String(localized: "Open Finder Selection in \(app.name)", bundle: .floe, comment: "The placeholder is an app's name.")
        case let .event(event): event.title
        case let .snippet(snippet): snippet.name
        case let .emoji(entry): entry.name
        case let .quicklink(link, queryText, fallback, keywordSearch):
            if fallback || keywordSearch {
                String(localized: "Search \(link.name) for \u{201C}\(queryText)\u{201D}", bundle: .floe, comment: "The first placeholder is the name of a site or quicklink, the second is what the user typed.")
            } else {
                link.name
            }
        case let .file(file): file.name
        case let .browserTab(row): row.title
        case let .clipboardEntry(entry): entry.title.isEmpty ? entry.kind.rawValue.capitalized : entry.title
        case let .menuBarItem(_, name): name
        case .menuBarAccess: String(localized: "Floe needs Accessibility to list your menu bar items", bundle: .floe, comment: "Accessibility is the name of a permission in System Settings.")
        case let .askAI(question): String(localized: "Ask AI \u{201C}\(question)\u{201D}", bundle: .floe, comment: "The placeholder is the question the user typed.")
        case let .webAddress(address): String(localized: "Open \(address.text)", bundle: .floe, comment: "The placeholder is a web address.")
        case let .sshHost(host, _): host.alias
        case let .shortcut(shortcut): shortcut.name
        }
    }

    var subtitle: String? {
        switch self {
        case let .command(command):
            return command.extensionTitle
        case let .script(script):
            return script.displayPackage
        case let .emoji(entry):
            return entry.character
        case let .quicklink(link, _, _, _):
            return link.keyword
        case .system:
            return String(localized: "System", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a system command such as Sleep.")
        case let .event(event):
            return event.subtitle
        case let .snippet(snippet):
            return snippet.firstLine
        case let .sshHost(host, _):
            return host.subtitle
        default:
            return nil
        }
    }

    /// Key for aliases and hotkeys; commands keep their historical "extension/command" key.
    var settingsKey: String? {
        switch self {
        case .app, .sshHost, .shortcut: id
        case let .command(command): command.id
        case let .script(script): script.id
        case .menuBarSearch: Self.menuBarSearchKey
        case .emojiSearch: Self.emojiSearchKey
        case .clipboardHistory, .clipboardApp: Self.clipboardHistoryKey
        case .fileSearch: Self.fileSearchKey
        case let .system(command): "system:\(command.rawValue)"
        case .snippet: id
        case .settings, .settingsPane, .note, .thaw, .finderSelection, .calculator, .emoji, .quicklink, .searchFiles, .event: nil
        case .file, .clipboardEntry, .menuBarItem, .menuBarAccess, .browserTab, .askAI, .webAddress: nil
        }
    }

    var kind: String {
        switch self {
        case .app: String(localized: "Application", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case let .command(command) where command.mode == "menu-bar": String(localized: "Menu Bar", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .command: String(localized: "Command", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .script: String(localized: "Script", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .menuBarSearch, .emojiSearch, .clipboardHistory, .settings: "Floe"
        case let .clipboardApp(destination): destination.label
        case .fileSearch, .searchFiles: String(localized: "Files", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .calculator: String(localized: "Calculator", bundle: .floe)
        case .system: String(localized: "System", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a system command such as Sleep.")
        case .settingsPane: String(localized: "System Settings", bundle: .floe)
        case .note: String(localized: "Notes", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a row that writes a note.")
        case .thaw: "Thaw"
        case .finderSelection: "Finder"
        case .event: String(localized: "Event", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a calendar event.")
        case .snippet: String(localized: "Snippet", bundle: .floe, comment: "The kind of a result, shown beside its title. A snippet is a saved piece of text.")
        case .emoji: String(localized: "Emoji", bundle: .floe)
        case .quicklink: String(localized: "Quicklink", bundle: .floe, comment: "The kind of a result, shown beside its title. A quicklink is a saved link or search.")
        case .file: String(localized: "File", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .browserTab: String(localized: "Browser Tab", bundle: .floe)
        case .clipboardEntry: String(localized: "Clipboard", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .menuBarItem, .menuBarAccess: String(localized: "Menu Bar", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .askAI: String(localized: "AI", bundle: .floe, comment: "The kind of a result, shown beside its title. Short for artificial intelligence.")
        case .webAddress: String(localized: "Web Address", bundle: .floe)
        case .sshHost: "SSH"
        case .shortcut: String(localized: "Shortcut", bundle: .floe, comment: "The kind of a result, shown beside its title. Here one made in Apple's Shortcuts app.")
        }
    }

    var isCalculator: Bool {
        if case .calculator = self { return true }
        return false
    }
}
