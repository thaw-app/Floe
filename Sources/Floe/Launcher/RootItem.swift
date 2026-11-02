//
//  RootItem.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One row of the root search, with the section it stands under.
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
    /// An extension command offered as a fallback, run with what was typed.
    case fallbackCommand(ExtensionCommand, text: String)
    case script(ScriptCommand)
    case menuBarSearch
    /// The commands in the menus of the app in front, to choose one from the keyboard.
    case menuItemSearch
    case emojiSearch
    case clipboardHistory
    /// The notes of the folder the user chose, to read and write in the panel.
    case noteDesk
    /// A note kept on top of other apps, in a window of its own, from the notes app the user chose.
    case floatingNote
    /// Clipboard History while another app keeps the history: the same command, opened there.
    case clipboardApp(ClipboardDestination)
    case fileSearch
    case searchFiles(String)
    case settings
    /// The Extension Store page of Settings, where extensions are found and installed.
    case extensionStore
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
    /// A command line: the one typed after the prefix, or one offered under it. With the terminal it may be handed to.
    /// The typed one's id leaves the command out.
    case shell(ShellRow, terminal: ResolvedApp?)
    /// A running process, found by `kill` and a name; Return asks it to quit.
    case process(RunningProcess)
    /// Something Floe did, listed by `receipts`; Return puts back what went to the Trash.
    case receipt(Receipt)
    /// A saved checkpoint; Return opens what it holds.
    case checkpoint(Checkpoint)
    /// The row that saves a checkpoint under the name typed after `pause`.
    case checkpointDraft(name: String, note: String)
    /// The row that adds a reminder from the sentence typed after `remind`.
    case reminderDraft(ReminderDraft)
    /// The row that adds a calendar event from the sentence typed after `event`.
    case eventDraft(EventDraft)
    /// The row that starts a timer from what was typed after `timer`, or a timer that is counting down.
    case timer(TimerRow)
    /// A person from Contacts, found by `contact` and a name, or the row that stands in for them until Floe may read them.
    case contact(ContactRow)
    /// The row that opens a mail or message draft from what was typed after `mail` or `message`.
    case outgoing(OutgoingDraft)
    /// Toggle Focus, or the row for what was typed after `focus`. With the Shortcut that sets it, empty while none is named.
    case focus(FocusRequest, shortcut: String)
    /// A word the search answers to, listed by `keywords`; Return types it into the search.
    case keyword(KeywordHint)
    /// What the dictionary says about the word typed after `define`; Return opens it in the Dictionary app.
    case definition(WordDefinition)
    /// Something worked out from the query, such as a time elsewhere or a new identifier; Return copies it.
    case answer(AnswerRow)
    /// A command of the front app's menus, found by `menus`, or the row that stands in for them until Floe may read them.
    case menuItem(MenuItemRow)
    /// An open window, found by `windows` and its title, or the row that stands in for them until Floe may read them.
    case window(WindowRow)
    /// A bookmark of one of the browsers, found by `bookmarks`; Return opens it.
    case bookmark(WebBookmark)
    /// A device sound plays through or is recorded by, found by "output" or "input"; Return makes it the one in use.
    case soundDevice(SoundDeviceRow)
    /// The QR code for what was typed after "qr"; Return copies the picture.
    case qrCode(String)
    /// A place Apple Maps found for what was typed after "maps"; Return shows it in Maps.
    case place(Place)
    /// A Homebrew package, found by "brew" and its name; Return installs it in the terminal, or upgrades it.
    case brew(BrewPackage)

    static let menuBarSearchKey = "builtin:menubar-search"
    static let menuItemSearchKey = "builtin:menu-item-search"
    static let emojiSearchKey = "builtin:emoji-search"
    static let clipboardHistoryKey = "builtin:clipboard-history"
    static let fileSearchKey = "builtin:file-search"
    static let noteDeskKey = "builtin:notes"
    static let floatingNoteKey = "builtin:floating-note"

    var id: String {
        switch self {
        case let .app(app): "app:\(app.url.path)"
        case let .command(command): "command:\(command.id)"
        case let .fallbackCommand(command, _): "fallback-command:\(command.id)"
        case let .script(script): "script:\(script.file.lastPathComponent)"
        case .menuBarSearch: Self.menuBarSearchKey
        case .menuItemSearch: Self.menuItemSearchKey
        case .emojiSearch: Self.emojiSearchKey
        case .clipboardHistory, .clipboardApp: Self.clipboardHistoryKey
        case .fileSearch: Self.fileSearchKey
        case .noteDesk: Self.noteDeskKey
        case .floatingNote: Self.floatingNoteKey
        case let .searchFiles(query): "files-for:\(query)"
        case .settings: "settings"
        case .extensionStore: "extension-store"
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
        case let .shell(row, _): row.origin == .typed ? "shell-command" : "shell-suggestion:\(row.origin.rawValue):\(row.text)"
        case let .process(process): "process:\(process.pid)"
        case let .receipt(receipt): "receipt:\(receipt.id.uuidString)"
        case let .checkpoint(checkpoint): "checkpoint:\(checkpoint.id.uuidString)"
        case .checkpointDraft: "checkpoint-draft"
        case .reminderDraft: "reminder-draft"
        case .eventDraft: "event-draft"
        case let .timer(row): row.id
        case let .contact(row): row.id
        case let .outgoing(draft): "\(draft.kind.rawValue)-draft"
        case let .focus(request, _): request == .toggle ? "focus-toggle" : "focus-request"
        case let .keyword(hint): "keyword:\(hint.keyword)"
        case let .definition(definition): "definition:\(definition.word)"
        case let .answer(row): row.id
        case let .menuItem(.item(entry, target)): "menu-item:\(target.pid):\(entry.pathKey)"
        case .menuItem(.access): "menu-item-access"
        case let .window(.window(window)): "window:\(window.id)"
        case .window(.access): "window-access"
        case let .bookmark(bookmark): "bookmark:\(bookmark.url.absoluteString)"
        case let .brew(package): "brew:\(package.isCask ? "cask" : "formula"):\(package.name)"
        case let .soundDevice(row): "sound:\(row.device.id)"
        case .qrCode: "qr-code"
        case let .place(place): "place:\(place.latitude),\(place.longitude):\(place.name)"
        }
    }

    var title: String {
        switch self {
        case let .app(app): app.name
        case let .command(command): command.title
        case let .fallbackCommand(command, text): String(localized: "\(command.title) \u{201C}\(text)\u{201D}", bundle: .floe, comment: "A fallback row: the first placeholder is a command's name, the second is what the user typed.")
        case let .script(script): script.title
        case .menuBarSearch: String(localized: "Search Menu Bar Items", bundle: .floe)
        case .menuItemSearch: String(localized: "Search Menu Items", bundle: .floe, comment: "The command that lists the commands in the menus of the app in front.")
        case .emojiSearch: String(localized: "Search Emoji & Symbols", bundle: .floe)
        case .clipboardHistory, .clipboardApp: String(localized: "Clipboard History", bundle: .floe)
        case .fileSearch: String(localized: "Search Files", bundle: .floe)
        case .noteDesk: String(localized: "Browse Notes", bundle: .floe, comment: "The command that shows the user's notes in the panel, to read and write them.")
        case .floatingNote: String(localized: "Floating Note", bundle: .floe, comment: "The command, and the window, that keep a note on top of other apps.")
        case let .searchFiles(query): String(localized: "Search Files for \"\(query)\"", bundle: .floe, comment: "The placeholder is what the user typed.")
        case .settings: String(localized: "Floe Settings", bundle: .floe)
        case .extensionStore: SearchPaneLabel.extensionStore.title
        case let .calculator(_, result, error, _):
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
        case let .process(process): process.name
        case let .receipt(receipt): receipt.title
        case let .checkpoint(checkpoint): String(localized: "Resume \(checkpoint.name)", bundle: .floe, comment: "The placeholder is the name the user gave a checkpoint.")
        case let .checkpointDraft(name, _): String(localized: "Save Checkpoint “\(name)”", bundle: .floe, comment: "The placeholder is the name the user typed for a checkpoint.")
        case let .reminderDraft(draft): String(localized: "Remind: \(draft.title)", bundle: .floe, comment: "The title of the row that adds a reminder. The placeholder is what the reminder is about, such as call mom.")
        case let .eventDraft(draft): String(localized: "Event: \(draft.title)", bundle: .floe, comment: "The title of the row that adds a calendar event. The placeholder is what the event is called, such as lunch with Ana.")
        case let .timer(row): row.title
        case let .contact(row): row.title
        case let .outgoing(draft): draft.title
        case let .focus(request, _): request.title
        case let .keyword(hint): hint.example
        case let .definition(definition): definition.text
        case let .answer(row): row.title
        case let .menuItem(.item(entry, _)): entry.title
        case .menuItem(.access): String(localized: "Floe needs Accessibility to read the menus of the app in front", bundle: .floe, comment: "Accessibility is the name of a permission in System Settings.")
        case let .window(.window(window)): window.title
        case let .bookmark(bookmark): bookmark.title
        case let .brew(package): package.name
        case let .soundDevice(row): row.device.name
        case let .place(place): place.name
        case let .qrCode(text): String(localized: "QR Code for \(text)", bundle: .floe, comment: "The placeholder is the text or the link the code holds.")
        case .window(.access): String(localized: "Floe needs Accessibility to list your windows", bundle: .floe, comment: "Accessibility is the name of a permission in System Settings.")
        case let .shell(row, _): row.origin == .typed ? String(localized: "Run \(row.text)", bundle: .floe, comment: "The placeholder is a shell command the user typed.") : row.text
        }
    }

    var subtitle: String? {
        switch self {
        case let .command(command), let .fallbackCommand(command, _):
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
        case let .answer(row):
            return row.subtitle
        case let .menuItem(.item(entry, _)):
            return entry.menuPath.isEmpty ? nil : entry.menuPath
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
        case .menuItemSearch: Self.menuItemSearchKey
        case .emojiSearch: Self.emojiSearchKey
        case .clipboardHistory, .clipboardApp: Self.clipboardHistoryKey
        case .fileSearch: Self.fileSearchKey
        case .noteDesk: Self.noteDeskKey
        case .floatingNote: Self.floatingNoteKey
        case let .system(command): "system:\(command.rawValue)"
        case .snippet: id
        case let .focus(request, _): request == .toggle ? id : nil
        case .settings, .extensionStore, .settingsPane, .note, .thaw, .finderSelection, .calculator, .emoji, .quicklink, .searchFiles, .event, .fallbackCommand: nil
        case .file, .clipboardEntry, .menuBarItem, .menuBarAccess, .browserTab, .askAI, .webAddress, .shell, .process, .receipt, .checkpoint, .checkpointDraft, .reminderDraft, .eventDraft, .timer, .contact, .outgoing, .keyword, .definition, .answer, .menuItem, .window, .bookmark, .brew, .soundDevice, .qrCode, .place: nil
        }
    }
}

extension RootItem {
    var kind: String {
        switch self {
        case .app: String(localized: "Application", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case let .command(command) where command.mode == "menu-bar": String(localized: "Menu Bar", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .command, .fallbackCommand: String(localized: "Command", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .script: String(localized: "Script", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .menuBarSearch, .menuItemSearch, .emojiSearch, .clipboardHistory, .noteDesk, .floatingNote, .settings, .extensionStore: "Floe"
        case let .clipboardApp(destination): destination.label
        case .fileSearch, .searchFiles: String(localized: "Files", bundle: .floe, comment: "The kind of a result, shown beside its title.")
        case .calculator: String(localized: "Calculator", bundle: .floe)
        case .system: String(localized: "System", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a system command such as Sleep.")
        case .settingsPane: String(localized: "System Settings", bundle: .floe)
        case .note: String(localized: "Notes", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a row that writes a note.")
        case .thaw: "Thaw"
        case .finderSelection: "Finder"
        case .event, .eventDraft: String(localized: "Event", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a calendar event.")
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
        case .checkpoint, .checkpointDraft: String(localized: "Checkpoint", bundle: .floe, comment: "The kind of a result, shown beside its title. A checkpoint is a saved set of files, tabs and a note.")
        case .reminderDraft: String(localized: "Reminder", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a row that adds a reminder.")
        case let .outgoing(draft) where draft.kind == .mail: String(localized: "Mail", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a row that opens an email draft.")
        case .outgoing: String(localized: "Message", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a row that opens a message draft.")
        case .focus: String(localized: "Focus", bundle: .floe, comment: "The kind of a result, shown beside its title. Focus is the macOS feature that silences notifications.")
        case .keyword: String(localized: "Keyword", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a word the search answers to.")
        case .definition: String(localized: "Dictionary", bundle: .floe, comment: "The kind of a result, shown beside its title. Here what the dictionary says about a word.")
        case let .answer(row): row.kind
        case .bookmark: String(localized: "Bookmark", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a page saved in a browser.")
        case .brew: "Homebrew"
        case .place: String(localized: "Place", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a place on the map.")
        case .qrCode: String(localized: "QR Code", bundle: .floe, comment: "The kind of a result, shown beside its title, and the name of the file it is saved as.")
        case let .soundDevice(row): SoundDeviceScope(role: row.device.role).title
        case .menuItem: String(localized: "Menu Item", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a command in the menus of the app in front.")
        case .window: String(localized: "Window", bundle: .floe, comment: "The kind of a result, shown beside its title. Here an open window of an app.")
        case .contact: String(localized: "Contact", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a person from Contacts.")
        case .timer: String(localized: "Timer", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a countdown.")
        case .receipt: String(localized: "Receipt", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a record of something Floe did.")
        case .process: String(localized: "Process", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a running program.")
        case let .shell(row, _): row.origin.label
        case .shortcut: String(localized: "Shortcut", bundle: .floe, comment: "The kind of a result, shown beside its title. Here one made in Apple's Shortcuts app.")
        }
    }

    /// The page of Settings a row opens. Nil for Floe Settings itself, which opens where it was left.
    var settingsPage: SettingsPage? {
        if case .extensionStore = self {
            return .extensionStore
        }
        return nil
    }

    var isCalculator: Bool {
        if case .calculator = self {
            return true
        }
        return false
    }
}
