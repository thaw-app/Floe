//
//  Model+Keys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The panel's keys, for whichever view is on screen.
extension LauncherModel {
    /// Return, Tab, the keys that move the selection, and anything held with Command or Control.
    static func actsOnResults(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        LauncherPanelState.isRowKey(keyCode, flags: flags) || [48, 76].contains(keyCode) || !flags.isDisjoint(with: [.command, .control])
    }

    /// A key that acts on the results acts on those of the text as typed. A typed letter waits with the rest.
    private func settleTyping(before keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        if Self.actsOnResults(keyCode, flags: flags) {
            typing.flush()
        }
    }

    /// Returns true when the key was consumed. Each mode's own keys are its model's.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        settleTyping(before: event.keyCode, flags: flags)
        pointerRest.rest()
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
        if let menuItemSearch {
            return menuItemSearch.handleKey(event, flags)
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

    /// Return goes ahead and Escape does not; any other key is held back, so nothing changes behind the question.
    func answer(_ question: PanelQuestion, with event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: answer(question, yes: true)
        case 53: answer(question, yes: false)
        default: break
        }
        return true
    }

    func answer(_ question: PanelQuestion, yes: Bool) {
        self.question = nil
        if yes {
            question.goAhead()
        }
    }

    /// Shows a question over whatever the panel shows, bringing the panel up for a command run by its hotkey.
    /// Asked from an app's hotkey, such as Force Quit, it is answered after the hotkey is done: going ahead then
    /// leaves the panel as the hotkey would, so a held command is not ended by the answer.
    func ask(_ question: PanelQuestion) {
        var asked = question
        if isRunningAppHotkey {
            asked = PanelQuestion(title: question.title, detail: question.detail, button: question.button) { [weak self] in
                let running = self?.isRunningAppHotkey ?? false
                self?.isRunningAppHotkey = true
                defer { self?.isRunningAppHotkey = running }
                question.goAhead()
            }
        }
        self.question = asked
        panelHost.showPanel()
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
        // The selected row's keys come first: its owner's, its actions', and Tab and Space.
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
        activate(results[selection].item, flags: flags)
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
        if session.actionMenuOpen, session.handleActionPanelKey(event, flags) {
            return true
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            session.moveSelection(by: delta)
            return true
        }
        switch event.keyCode {
        case 123, 124:
            return session.stepInGrid(by: event.keyCode == 123 ? -1 : 1)
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
}
