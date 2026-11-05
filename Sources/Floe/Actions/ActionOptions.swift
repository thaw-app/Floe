//
//  ActionOptions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import ThawUI

/// One of Floe's own rows of a kind's Actions menu, as Settings lists it.
struct ActionOption: Identifiable, Equatable {
    let id: ActionID
    let title: String
    /// A submenu does nothing itself: it can be left out of the menu, but takes no keys and is no choice for Return.
    var isSubmenu = false
}

extension ActionOption {
    /// Floe's own rows on a kind of result, in the order its Actions menu has them. A row only some results have,
    /// such as Quit, is listed all the same; one that depends on the result, such as an app in Open With, is left to
    /// its submenu's row. `roleApps` are the roles a file opens in with their apps, as the launcher resolves them.
    /// The user's scripts that act on the kind come after Floe's rows, as the menu has them.
    static func rows(for kind: SubjectKind, roleApps: [RoleApp], scripts: [ScriptCommand] = []) -> [ActionOption] {
        floeRows(for: kind, roleApps: roleApps)
            + scripts.filter { $0.subjects.contains(kind) }.map { ActionOption(id: $0.actionID, title: $0.title) }
    }

    private static func floeRows(for kind: SubjectKind, roleApps: [RoleApp]) -> [ActionOption] {
        let openWith = ActionOption(id: .openWith, title: String(localized: "Open With", bundle: .floe, comment: "The title of a submenu that lists apps."), isSubmenu: true)
        let roles = roleApps.map { entry in
            ActionOption(id: .openIn(entry.role), title: String(localized: "Open in \(entry.app.name)", bundle: .floe, comment: "The placeholder is the name of an app."))
        }
        let showInFinder = ActionOption(id: .showInFinder, title: String(localized: "Show in Finder", bundle: .floe))
        let quickLook = ActionOption(id: .quickLook, title: String(localized: "Quick Look", bundle: .floe, comment: "The name of the macOS feature that previews a file."))
        let copies = [
            ActionOption(id: .copyPath, title: String(localized: "Copy Path", bundle: .floe)),
            ActionOption(id: .copyName, title: String(localized: "Copy Name", bundle: .floe)),
        ]
        let copyFile = ActionOption(id: .copyFile, title: String(localized: "Copy File", bundle: .floe))
        let trash = ActionOption(id: .moveToTrash, title: String(localized: "Move to Trash…", bundle: .floe))
        switch kind {
        case .app:
            // An app found as a file, such as by its path, has a file's menu, so its rows are an app's too.
            return [
                ActionOption(id: .hide, title: String(localized: "Hide", bundle: .floe, comment: "An action that hides a running app's windows.")),
                ActionOption(id: .quit, title: String(localized: "Quit", bundle: .floe, comment: "An action that quits a running app.")),
                ActionOption(id: .restart, title: String(localized: "Restart", bundle: .floe, comment: "An action that quits a running app and opens it again.")),
                ActionOption(id: .forceQuit, title: String(localized: "Force Quit…", bundle: .floe)),
                openWith,
            ] + roles + [showInFinder, quickLook] + copies + [
                copyFile,
                ActionOption(id: .copyBundleIdentifier, title: String(localized: "Copy Bundle Identifier", bundle: .floe)),
                trash,
                ActionOption(id: .toggleFavorite, title: String(localized: "Add to or Remove from Favorites", bundle: .floe, comment: "An action on an app, as Settings lists it. The Actions menu shows Add to Favorites or Remove from Favorites, whichever the app needs.")),
                ActionOption(id: .hideFromSearch, title: String(localized: "Hide from Search", bundle: .floe)),
            ]
        case .file, .folder:
            return [openWith] + roles + [showInFinder, quickLook] + copies + [copyFile, trash]
        case .url:
            return [openWith, ActionOption(id: .copyAddress, title: String(localized: "Copy Address", bundle: .floe))]
        }
    }
}

extension SubjectKind {
    /// The kind's name on the buttons that pick it in Settings.
    var title: String {
        switch self {
        case .app: String(localized: "Apps", bundle: .floe, comment: "Results that are apps, as one of the kinds of result whose actions are chosen in Settings.")
        case .file: String(localized: "Files", bundle: .floe, comment: "Results that are files, as one of the kinds of result whose actions are chosen in Settings.")
        case .folder: String(localized: "Folders", bundle: .floe, comment: "Results that are folders, as one of the kinds of result whose actions are chosen in Settings.")
        case .url: String(localized: "Links", bundle: .floe, comment: "Results that are web addresses or bookmarks, as one of the kinds of result whose actions are chosen in Settings.")
        }
    }

    /// What Floe does on Return with nothing chosen, named as the first row of the kind's Actions menu names it: a
    /// link opens in the browser the user chose.
    func floeActionTitle(browser: BrowserMenu) -> String {
        switch self {
        case .url: browser.openTitle
        case .app, .file, .folder: String(localized: "Open", bundle: .floe, comment: "A verb on a button: open the selected result.")
        }
    }
}

/// What Settings changes in the choices for one kind.
extension KindActions {
    /// What Return does, as Settings shows it: the first default that is a row listed and can run, or nil for what
    /// Floe does. A default not listed, such as the editor's row once no editor is found, is passed over here as the
    /// launcher passes it over.
    func returnChoice(among rows: [ActionOption]) -> ActionID? {
        defaults.first { id in rows.contains { $0.id == id && !$0.isSubmenu } }
    }

    /// Return does this row from now on, or with nil what Floe does.
    mutating func setReturnChoice(_ id: ActionID?) {
        defaults = id.map { [$0] } ?? []
    }

    func shows(_ id: ActionID) -> Bool {
        !hidden.contains(id)
    }

    mutating func setShown(_ isShown: Bool, for id: ActionID) {
        if isShown {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
    }

    /// The keys that run a row: Floe's for the kind, with the user's laid over them and none of Floe's hotkeys, as
    /// the launcher has them.
    func keys(for id: ActionID, of kind: SubjectKind, hotkeys: Set<KeyCombination> = []) -> KeyCombination? {
        ActionKeys.inForce(for: kind, choices: self, hotkeys: hotkeys).key(for: id)
    }

    /// Gives a row keys, or with nil takes its keys away, Floe's included. Floe's own keys for the row are stored as
    /// nothing chosen, which is how a row gets them back. Keys refused change nothing, and the refusal says why.
    /// `hotkeys` are Floe's own, which the Mac takes before a row could. Only the rows listed hold keys against
    /// others: a row no longer listed could not be given other keys to free them.
    mutating func setKeys(
        _ keys: KeyCombination?,
        for id: ActionID,
        of kind: SubjectKind,
        among rows: [ActionOption],
        hotkeys: Set<KeyCombination> = []
    ) -> KeyRefusal? {
        let floes = ActionKeys.floe(for: kind).key(for: id)
        guard let keys else {
            shortcuts[id] = nil
            if floes == nil {
                clearedKeys.remove(id)
            } else {
                clearedKeys.insert(id)
            }
            return nil
        }
        if let refusal = KeyRefusal(keys, for: id, in: self, of: kind, among: rows, hotkeys: hotkeys) {
            return refusal
        }
        shortcuts[id] = keys == floes ? nil : keys
        clearedKeys.remove(id)
        return nil
    }
}

/// Why keys were not given to a row.
enum KeyRefusal: Equatable {
    /// One of Floe's own hotkeys, such as the one that opens it: the Mac takes it before a row could.
    case hotkey(KeyCombination)
    /// Without Command the keys would be typed into the search field.
    case needsCommand(KeyCombination)
    /// The launcher, the search field or the main menu already use them.
    case reserved(KeyCombination)
    /// Another row of the kind has them, named by its title.
    case taken(KeyCombination, by: String)

    /// Why these keys cannot be the row's, or nil when they can. Floe's hotkeys are never a row's. The launcher's own
    /// rule decides what the user can choose, but Floe's own keys for the row are always the row's. The keys another
    /// row has are those in force on it, Floe's included.
    init?(
        _ keys: KeyCombination,
        for id: ActionID,
        in choices: KindActions,
        of kind: SubjectKind,
        among rows: [ActionOption],
        hotkeys: Set<KeyCombination> = []
    ) {
        if hotkeys.contains(keys) {
            self = .hotkey(keys)
            return
        }
        if keys != ActionKeys.floe(for: kind).key(for: id), !AlternativeActionRules.canBeChosen(keys) {
            self = keys.modifiers.contains(.command) ? .reserved(keys) : .needsCommand(keys)
            return
        }
        let inForce = ActionKeys.inForce(for: kind, choices: choices, hotkeys: hotkeys)
        guard let other = rows.first(where: { $0.id != id && inForce.key(for: $0.id) == keys }) else { return nil }
        self = .taken(keys, by: other.title)
    }

    /// The line Settings shows under the row.
    var message: String {
        switch self {
        case let .hotkey(keys):
            String(localized: "\(keys.displayValue) is one of Floe's hotkeys, so it can't also run an action.", bundle: .floe, comment: "The placeholder is a key combination, such as ⌥ ⇧ Space, that opens Floe or runs a command from anywhere.")
        case let .needsCommand(keys):
            String(localized: "\(keys.displayValue) has no Command key. An action's keys need it, so they never take what you type in the search.", bundle: .floe, comment: "The placeholder is a key combination, such as ⌥ K.")
        case let .reserved(keys):
            String(localized: "\(keys.displayValue) already does something in the launcher.", bundle: .floe, comment: "The placeholder is a key combination, such as ⌘ K.")
        case let .taken(keys, title):
            String(localized: "\(keys.displayValue) is already the keys for \(title).", bundle: .floe, comment: "The first placeholder is a key combination, such as ⌘ K; the second is the name of an action, such as Copy Path.")
        }
    }
}

extension [String: KindActions] {
    /// The choices for a kind, or nothing chosen. Choices set back to nothing leave the dictionary, so a kind with
    /// none is neither saved nor synced.
    subscript(kind kind: SubjectKind) -> KindActions {
        get { self[kind.rawValue] ?? KindActions() }
        set { self[kind.rawValue] = newValue == KindActions() ? nil : newValue }
    }
}
