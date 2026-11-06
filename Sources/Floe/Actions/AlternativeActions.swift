//
//  AlternativeActions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ThawUI

/// The user's choices on apps, files, folders and web addresses: what Return does, which rows the Actions menu
/// shows, and the keys on its rows. Nothing chosen leaves every result as Floe has it. Script commands with a
/// `@floe.subjects` line are rows of the user's own, after Floe's.
final class AlternativeActions {
    /// What the feature asks of the launcher.
    struct Host {
        var choices: () -> [String: KindActions] = { [:] }
        /// The rows of a result's Actions menu after its Return row, the user's scripts on it among them.
        var floeActions: (RootItem) -> [ItemAction?] = { _ in [] }
        /// What Floe's own Return on a result is called.
        var floeTitle: (RootItem) -> String = { _ in "" }
        /// Does what Floe's own Return does.
        var openAsFloeDoes: (RootItem) -> Void = { _ in
            // Set by LauncherFeatures.
        }

        /// Counts the result as used, where opening it would.
        var used: (RootItem) -> Void = { _ in
            // Set by LauncherFeatures.
        }

        /// What the rows on offer depend on that changes while the result stays the same, such as whether an app
        /// runs and is hidden, whether it is a favorite, or the app an Open in row opens. The Return title is worked
        /// out again when it changes.
        var offerState: (RootItem) -> Int = { _ in 0 }
        /// Floe's own hotkeys, which no row's keys can be.
        var hotkeys: () -> Set<KeyCombination> = { [] }
        /// The user's script commands, those that act on results among them.
        var scripts: () -> [ScriptCommand] = { [] }
        /// Runs a script on the result it acts on.
        var runScript: (ScriptCommand, ActionSubject) -> Void = { _, _ in
            // Set by LauncherFeatures.
        }
    }

    var host = Host()
    var kindOf: (RootItem) -> SubjectKind? = SubjectKind.of
    /// The last result's kind: the bottom bar asks on every draw, and a file's is read from the disk.
    private var lastKind: (id: String, kind: SubjectKind?)?
    /// The last Return title, for the same reason: working it out builds the result's rows.
    private var lastTitle: (id: String, choices: KindActions, state: Int, title: String?)?

    // MARK: - What the launcher asks

    /// Return on a result, when a default applies to it. False leaves the result to Floe.
    func open(_ item: RootItem, flags: NSEvent.ModifierFlags) -> Bool {
        // Return with keys held means what Floe gives it on the row.
        guard flags.isEmpty, let action = primary(for: item) else { return false }
        host.used(item)
        action.run()
        return true
    }

    /// What Return does on a result, when it is not Floe's own.
    func returnTitle(for item: RootItem) -> String? {
        guard let choices = choices(for: item), !choices.defaults.isEmpty else { return nil }
        let state = host.offerState(item)
        if let lastTitle, lastTitle.id == item.id, lastTitle.choices == choices, lastTitle.state == state {
            return lastTitle.title
        }
        let title = primary(for: item)?.title
        lastTitle = (item.id, choices, state, title)
        return title
    }

    /// The Actions menu: the Return row, then Floe's rows with the user's choices applied. When a default took
    /// Return, its row is the Return row and is not listed again, so the Return row shows its keys.
    func menu(_ returnRow: ItemAction, rows: [ItemAction?], for item: RootItem) -> [ItemAction?] {
        guard let choices = choices(for: item) else { return [returnRow] + rows }
        let primary = AlternativeActionRules.primary(choices, offered: AlternativeActionRules.offered(rows))
        var returnRow = returnRow
        returnRow.shortcut = primary?.shortcut
        let own = primary == nil ? nil : ownAction(for: item)
        return [returnRow] + AlternativeActionRules.arranged(rows, own: own, primaryID: primary?.id, choices: choices)
    }

    /// A result's rows with their keys: the view's own, then the user's scripts that act on its kind. Each view
    /// builds its rows here, so wherever a row has keys, the scripts are on offer to Return, the menu and keys too.
    func rows(_ own: [ItemAction?], for item: RootItem) -> [ItemAction?] {
        // Read again, as rows are built on a key or a menu, not on every draw: a path can be a folder by now.
        lastKind = nil
        let kind = kind(of: item)
        let scripts = scripts(on: kind)
        let keys = keys(of: kind, scripts: scripts)
        guard !scripts.isEmpty, let kind, let subject = ActionSubject.of(item, kind: kind) else { return keys.keyed(own) }
        let scriptRows = scripts.map { script -> ItemAction? in
            ItemAction(title: script.title, symbol: "terminal", id: script.actionID) { [host] in
                host.runScript(script, subject)
            }
        }
        return keys.keyed(own + [nil] + scriptRows)
    }

    /// The keys on a result's rows: Floe's for its kind, with the keys the user chose laid over them.
    func keys(for item: RootItem) -> ActionKeys {
        keys(of: kind(of: item))
    }

    /// The keys on the rows of a kind of result, as `keys(for:)` gives them on a result of that kind.
    func keys(of kind: SubjectKind?) -> ActionKeys {
        keys(of: kind, scripts: scripts(on: kind))
    }

    private func keys(of kind: SubjectKind?, scripts: [ScriptCommand]) -> ActionKeys {
        ActionKeys.inForce(for: kind, choices: choices(of: kind), hotkeys: host.hotkeys(), scripts: Set(scripts.map(\.actionID)))
    }

    /// The user's scripts that act on a kind of result; none on a result with no kind.
    private func scripts(on kind: SubjectKind?) -> [ScriptCommand] {
        kind.map { host.scripts().acting(on: $0) } ?? []
    }

    // MARK: - Working it out

    /// What the user chose for the result's kind; nil when it has no kind, or nothing is chosen for it.
    private func choices(for item: RootItem) -> KindActions? {
        choices(of: kind(of: item))
    }

    private func choices(of kind: SubjectKind?) -> KindActions? {
        let all = host.choices()
        guard !all.isEmpty, let kind, let choices = all[kind.rawValue], choices != KindActions() else { return nil }
        return choices
    }

    private func kind(of item: RootItem) -> SubjectKind? {
        if let lastKind, lastKind.id == item.id {
            return lastKind.kind
        }
        let kind = kindOf(item)
        lastKind = (item.id, kind)
        return kind
    }

    /// The row Return runs, when a default applies. Floe's rows are only built when one is chosen.
    private func primary(for item: RootItem) -> ItemAction? {
        guard let choices = choices(for: item), !choices.defaults.isEmpty else { return nil }
        return AlternativeActionRules.primary(choices, offered: AlternativeActionRules.offered(host.floeActions(item)))
    }

    /// What Floe's own Return does, as a row that stays reachable once a default took its place.
    private func ownAction(for item: RootItem) -> ItemAction {
        ItemAction(title: host.floeTitle(item), symbol: "arrow.uturn.backward", id: .own) { [host] in
            host.openAsFloeDoes(item)
        }
    }
}
