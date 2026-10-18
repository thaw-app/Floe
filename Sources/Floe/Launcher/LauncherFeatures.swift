//
//  LauncherFeatures.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The launcher's features, each handed what it asks of the launcher. This is the one place that connects them
/// to the model; a feature knows only its host.
final class LauncherFeatures {
    /// Shell commands and running processes. Tests replace parts of its environment.
    let shell: ShellRows
    let checkpoints = CheckpointRows()
    let timers = TimerRows()
    let reminders = ReminderRows()
    let events = EventRows()
    let receipts = ReceiptRows()
    let contacts = ContactRows()
    let focus = FocusRows()
    let music = MusicRemote()
    let emoji = EmojiRows()
    let windows = WindowRows()
    let menuItems = MenuItemRows()
    let brew = BrewRows()
    let sound = SoundRows()
    let places = PlaceRows()
    let qrCodes = QRCodeRows()
    let shortcuts = ShortcutRows()
    let scripts = ScriptRows()
    let system = SystemRows()
    let notes: NoteRows
    let found = FoundRows()

    /// The features that own rows, asked in turn what a row's Return, actions and keys do.
    let rowOwners: [any RowOwner]

    init(model: LauncherModel) {
        shell = ShellRows(settings: model.settings)
        notes = NoteRows(settings: model.settings)
        rowOwners = [shell, checkpoints, timers, reminders, events, receipts, contacts, focus, emoji, windows, menuItems, brew, sound, places, qrCodes, shortcuts, scripts, system, notes, found]
        let links = Links(model: model)
        connectShell(links)
        connectKept(links)
        connectReaching(links)
        connectKeywords(links)
        connectSearched(links)
    }

    /// What most features ask of the launcher, each reaching the model without keeping it.
    private struct Links {
        weak var model: LauncherModel?

        var showHUD: (String) -> Void {
            { [weak model] in model?.panelHost.showHUD($0) }
        }

        var hidePanel: () -> Void {
            { [weak model] in model?.panelHost.hidePanel() }
        }

        var leave: () -> Void {
            { [weak model] in model?.leave() }
        }

        var record: (Receipt) -> Void {
            { [weak model] in model?.record($0) }
        }

        var reach: (URL?) -> Void {
            { [weak model] in model?.reach($0) }
        }

        var openLink: (URL) -> Void {
            { [weak model] in model?.openLink($0) }
        }

        var toResident: () -> ((PanelPacket) -> Void)? {
            { [weak model] in model?.panelHost.residentRequests }
        }

        /// Everything a row feature asks of the launcher, in one value.
        var row: RowHost {
            RowHost(showHUD: showHUD, hidePanel: hidePanel, leave: leave, reach: reach, record: record) { [weak model] in
                // A refresh leaves a scope with the same query alone, so the scope is let go first.
                model?.activeScope = nil
                model?.refresh()
            }
        }
    }

    private func connectShell(_ links: Links) {
        weak let model = links.model
        shell.host = ShellRows.Host(
            hidePanel: links.hidePanel,
            showHUD: links.showHUD,
            leave: {
                // Before the panel goes back to the root, which empties the search.
                model?.rememberQuery()
                model?.leave()
            },
            record: links.record,
            setQuery: {
                model?.query = $0
                model?.focusToken += 1
            },
            refresh: { model?.refresh() },
            scriptsChanged: { model?.catalog.reloadScripts() }
        )
    }

    /// The features that keep something: checkpoints, timers, reminders, events and the receipts of all of them.
    private func connectKept(_ links: Links) {
        weak let model = links.model
        checkpoints.host = CheckpointRows.Host(
            hidePanel: links.hidePanel,
            showHUD: links.showHUD,
            leave: links.leave,
            record: links.record,
            showOutput: { [shell] in shell.environment.showOutput($0, $1) },
            openLink: links.openLink,
            chosenEditor: {
                guard let model else { return nil }
                // Only an editor the user chose: the role's stand-in is the app text files open in anyway.
                return PreferredApps.chosenApp(model.settings.appChoice(for: .editor), installed: model.resolvedApps.lookup)
            }
        )
        timers.host = links.row
        timers.toResident = links.toResident
        reminders.host = links.row
        events.host = links.row
        events.openLink = links.openLink
        receipts.host = ReceiptRows.Host(
            hidePanel: links.hidePanel,
            showHUD: links.showHUD,
            refresh: { model?.refresh() },
            showOutput: { [shell] in shell.environment.showOutput($0, $1) },
            runCommand: { [shell] in shell.runShellCommand($0, terminal: nil) },
            commandsChanged: { model?.catalog.reloadCommands() },
            keepsReceipts: { model?.settings.keepsReceipts ?? false },
            toResident: links.toResident,
            deleter: { [events, checkpoints, timers, reminders] kind in
                switch kind {
                case .event: events.environment.delete
                case .checkpoint: checkpoints.deleteCheckpoint
                case .timer: timers.stopTimer
                default: reminders.environment.delete
                }
            }
        )
    }

    /// The features that reach someone or something outside: contacts, Focus, music and emoji.
    private func connectReaching(_ links: Links) {
        weak let model = links.model
        contacts.host = links.row
        focus.host = links.row
        focus.runShortcut = { name, input, say in
            model?.features.shortcuts.library.run(named: name, input: input, showHUD: say)
        }
        music.say = links.showHUD
        emoji.host = links.row
        emoji.recordUse = { model?.usage.recordUse(of: $0) }
    }

    /// The rows a keyword finds outside the catalog: windows, menu commands, Homebrew packages, sound devices, places and QR codes.
    private func connectKeywords(_ links: Links) {
        weak let model = links.model
        let host = links.row
        windows.host = host
        menuItems.host = host
        menuItems.openSearch = { model?.openMenuItemSearch() }
        brew.host = host
        brew.runInTerminal = { [shell] command in
            let terminal = model?.resolvedApps.apps.first { $0.role == .terminal }?.app
            shell.runShellCommand(command, terminal: terminal, inTerminal: true)
        }
        sound.host = host
        places.host = host
        qrCodes.host = host
    }

    /// The rows of what the search holds besides: shortcuts, scripts, system commands, notes and what it worked out.
    private func connectSearched(_ links: Links) {
        weak let model = links.model
        let host = links.row
        shortcuts.host = host
        shortcuts.isOn = { model?.settings.searchSources.contains(SearchSourceInfo.shortcuts.id) ?? false }
        shortcuts.listChanged = {
            // Nothing to redraw without a query: the shortcuts are only searched for.
            guard let model, !model.query.isEmpty else { return }
            model.refresh()
        }
        scripts.host = host
        scripts.typed = { model?.query ?? "" }
        scripts.recordUse = { model?.usage.recordUse(of: $0) }
        system.host = host
        system.controlMusic = { [music] in _ = music.controlMusic($0) }
        notes.host = host
        found.host = host
        found.typeQuery = {
            model?.query = $0
            model?.focusToken += 1
        }
    }
}
