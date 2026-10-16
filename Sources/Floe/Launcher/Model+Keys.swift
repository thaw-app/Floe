//
//  Model+Keys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The panel's keys, for whichever view is on screen.
extension LauncherModel {
    /// Returns true when the key was consumed. Each mode's own keys are its model's.
    func handleKey(_ event: NSEvent) -> Bool {
        // A key that acts on the results acts on those of the text as typed, not of a moment ago.
        typing.flush()
        pointerRest.rest()
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if setup != nil {
            return handleSetupKey(event)
        }
        if event.keyCode == 43, flags == .command {
            panelHost.hidePanel()
            panelHost.openSettings(nil)
            return true
        }
        if isSearchingMenuBar {
            return menuBarSearch.handleKey(event, flags)
        }
        if let session = runner.session, session.command.mode == "view", session.alert != nil {
            return handleAlertKey(event, session)
        }
        if isShowingClipboardHistory {
            return clipboardHistory.handleKey(event)
        }
        if isSearchingFiles {
            return fileSearch.handleKey(event, flags)
        }
        if let noteDesk {
            return noteDesk.handleKey(event, flags)
        }
        if let session = runner.session, session.command.mode == "view" {
            return session.failure == nil ? handleSessionKey(event, flags, session) : handleFailureKey(event, flags, session)
        }
        if let askAI {
            return askAI.handleKey(event, flags)
        }
        return handleRootKey(event, flags)
    }

    /// A setup form: Return submits it and Escape cancels; every other key is a field's.
    private func handleSetupKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: cancelSetup()
        case 36, 76: submitSetup()
        default: return false
        }
        return true
    }

    private func handleAlertKey(_ event: NSEvent, _ session: ExtensionSession) -> Bool {
        switch event.keyCode {
        case 36, 76: session.resolveAlert(true)
        case 53: session.resolveAlert(false)
        default: return false
        }
        return true
    }

    /// The error screen of a command that failed.
    private func handleFailureKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        switch event.keyCode {
        case 36: runner.retry()
        case 53: runner.end(session)
        case 8 where flags == [.command, .shift]: runner.copyFailure()
        default: return false
        }
        return true
    }

    /// The root search, when nothing else has the panel.
    private func handleRootKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if event.keyCode == 126, recallOlderQuery() {
            return true
        }
        // Tab, Space and Command-Y belong to the kind of row that is selected.
        if handleRowKey(event, flags) {
            return true
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, results.count - 1))
            typing.browsed()
            return true
        }
        switch event.keyCode {
        case 36: activateSelection(flags)
        case 53: if query.isEmpty {
                panelHost.hidePanel()
            } else {
                query = ""
            }
        case 3 where flags == [.command, .shift]:
            if results.indices.contains(selection) {
                toggleFavorite(results[selection].item)
            }
        case 40 where flags == .command:
            panelHost.showActions()
        default: return false
        }
        return true
    }

    /// Return on the selected result. With Command an emoji is copied, not pasted, and a shell command opens in a terminal.
    private func activateSelection(_ flags: NSEvent.ModifierFlags) {
        guard results.indices.contains(selection) else {
            refusal.refuse()
            return
        }
        let item = results[selection].item
        if !flags.isEmpty, openByOwner(item, flags: flags) {
            // A row whose owner gives Return with a key held a meaning of its own.
        } else {
            activate(item)
        }
    }

    /// The keys of an extension's view, for whichever of its states is on screen. Internal, so the
    /// tests of routing can hand it events the way the key monitor does.
    func handleSessionKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        // In a form, arrows and Return belong to the fields; ⌘↵ submits.
        if let formKey = handleFormKey(event, flags, session) {
            return formKey
        }
        // A shortcut an action declared is its own, menu open or not: ⇧↵ with the Actions menu on
        // screen runs the action that declared it, and not the one the menu happens to highlight.
        if !flags.isEmpty, runDeclaredShortcut(event, flags, session) {
            return true
        }
        if session.actionMenuOpen, handleActionMenuKey(event, flags, session) {
            return true
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            session.moveSelection(by: delta)
            return true
        }
        switch event.keyCode {
        case 53:
            session.send(["type": "pop"])
        case 33 where flags == .command:
            session.send(["type": "pop"])
        case 36:
            runReturnAction(event, flags, session)
        case 40 where flags == .command:
            session.actionMenuOpen = true
        default:
            return false
        }
        return true
    }

    /// A form's own keys, when the view on screen is one: arrows and Return belong to the fields,
    /// and ⌘↵ submits. Nil when this is no form, or a key the fields have no claim on.
    private func handleFormKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool? {
        guard session.view?.type == "Form", !session.actionMenuOpen else { return nil }
        switch event.keyCode {
        case 125, 126: return false
        case 36 where flags != .command: return false
        case 36:
            if let action = session.actions.first {
                session.run(action)
            }
            return true
        default: return nil
        }
    }

    /// Return in a session: the main action, the second one with ⌘, or the action that declared Return
    /// with the modifiers pressed — ⇧↵, ⌃↵ and ⌥↵ belong to it, and not to the main action.
    private func runReturnAction(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) {
        let actions = session.actions
        if let declared = flags.isEmpty ? nil : actions.first(where: { Shortcuts.matches($0.props["shortcut"], key: Shortcuts.pressed(event), flags: flags) }) {
            session.run(declared)
            return
        }
        let index = flags == .command ? 1 : 0
        if actions.indices.contains(index) {
            session.run(actions[index])
        }
    }

    /// A key with modifiers that an action declared as its own shortcut, and false when none did.
    private func runDeclaredShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        guard !flags.isEmpty, let action = session.actions.first(where: { Shortcuts.matches($0.props["shortcut"], key: Shortcuts.pressed(event), flags: flags) }) else { return false }
        session.run(action)
        return true
    }

    /// While the action menu is open, typing searches it, ↵ runs or opens a submenu, ← and Esc step back.
    private func handleActionMenuKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            session.moveSelection(by: delta)
            return true
        }
        switch event.keyCode {
        case 36, 76: session.activateMenuEntry(at: session.actionSelection)
        case 53, 123: session.closeSubmenuOrMenu()
        case 124:
            let entries = session.menuEntries
            if entries.indices.contains(session.actionSelection), entries[session.actionSelection].isSubmenu {
                session.openSubmenu(entries[session.actionSelection].node)
            }
        case 40 where flags == .command: session.actionMenuOpen = false
        case 51: if !session.actionQuery.isEmpty {
                session.actionQuery.removeLast()
            }
        default:
            // Plain typing (Shift allowed) filters; anything with ⌘, ⌃ or ⌥ falls through to shortcuts.
            guard flags.subtracting(.shift).isEmpty, let characters = event.characters,
                  !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else {
                return false
            }
            session.actionQuery += characters
        }
        return true
    }
}
