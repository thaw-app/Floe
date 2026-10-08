//
//  Model+Actions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The Actions menu of the root search.
extension LauncherModel {
    private var actionHost: ActionHost {
        ActionHost(
            showHUD: { [weak self] in self?.showHUD($0) },
            dismiss: { [weak self] in
                self?.hidePanel()
                self?.reset()
            },
            preferredApps: preferredApps,
            record: { [weak self] in self?.record($0) }
        )
    }

    var selectedRootItem: RootItem? {
        results.indices.contains(selection) ? results[selection].item : nil
    }

    /// What Return does to a result, as its button and the first row of its menu say it.
    func primaryActionTitle(for item: RootItem) -> String {
        switch item {
        case let .command(command) where command.mode == "menu-bar":
            if isInMenuBar(command) {
                String(localized: "Remove from Menu Bar", bundle: .floe)
            } else {
                String(localized: "Add to Menu Bar", bundle: .floe)
            }
        case .clipboardEntry: String(localized: "Paste", bundle: .floe, comment: "A verb: insert what is on the clipboard.")
        case .askAI: String(localized: "Ask", bundle: .floe, comment: "A verb on a button: send the question to AI.")
        case .sshHost: String(localized: "Connect", bundle: .floe, comment: "A verb on a button: open an SSH connection to the host.")
        case .shortcut: String(localized: "Run", bundle: .floe, comment: "A verb on a button: run the shortcut or script.")
        case .menuBarItem: String(localized: "Click Item", bundle: .floe)
        case .browserTab(.tab): String(localized: "Switch to Tab", bundle: .floe)
        case .webAddress: openInBrowserTitle
        default: Self.laterTitle(for: item) ?? String(localized: "Open", bundle: .floe, comment: "A verb on a button: open the selected result.")
        }
    }

    /// Opens a scope's row the way its own view does: the file, the pasted entry, the clicked item.
    func openScopeResult(_ item: RootItem) {
        switch item {
        case let .file(file): fileSearch.open(file)
        case let .clipboardEntry(entry): clipboardHistory.paste(entry)
        case let .menuBarItem(extra, _): menuBarSearch.open(extra)
        case .menuBarAccess: openMenuBarSearch()
        case let .browserTab(.tab(tab)): switchToBrowserTab(tab)
        case let .browserTab(.access(browser)): SystemCommand.askForAutomation(toControl: browser.name)
        case let .webAddress(address): open(address)
        default: openLater(item)
        }
    }

    /// Brings a tab forward once the panel is gone. A refusal is answered here, where the user asked for the tab.
    private func switchToBrowserTab(_ tab: BrowserTab) {
        hidePanel()
        reset()
        BrowserTabs.activate(tab) { [weak self] outcome in
            switch outcome {
            case .text(BrowserTabScripts.switched): break
            case .refused: SystemCommand.askForAutomation(toControl: tab.browser.name)
            case .text, .failed: self?.showHUD(String(localized: "That tab is no longer open", bundle: .floe))
            }
        }
    }

    func rootActions(for item: RootItem) -> [ItemAction?] {
        var actions: [ItemAction?] = [
            ItemAction(title: primaryActionTitle(for: item), symbol: "return") { [weak self] in self?.activate(item) },
        ]
        switch item {
        case let .app(app):
            actions += [nil] + AppActions.actions(for: app, host: actionHost)
        case let .command(command):
            actions.append(ItemAction(title: String(localized: "Configure Extension…", bundle: .floe), symbol: "gearshape") { [weak self] in
                self?.hidePanel()
                self?.openSettings(command.extensionName)
            })
        case let .file(file):
            actions += FileActions.actions(for: file.url, host: actionHost)
        case let .sshHost(host, _):
            actions += SSHHostActions.actions(for: host, host: actionHost)
        case let .shortcut(shortcut):
            actions += shortcutActions(for: shortcut)
        case let .clipboardEntry(entry):
            actions.append(ItemAction(title: String(localized: "Copy", bundle: .floe, comment: "A verb: put the selection on the clipboard."), symbol: "doc.on.doc") { [weak self] in self?.clipboardHistory.copy(entry) })
        case .webAddress, .quicklink:
            actions += linkActions(for: item)
        default:
            actions += laterActions(for: item)
        }
        if Self.keepsItsPlace(item) {
            let favorite = isFavorite(item)
            actions += [
                nil,
                ItemAction(title: favorite ? String(localized: "Remove from Favorites", bundle: .floe) : String(localized: "Add to Favorites", bundle: .floe), symbol: favorite ? "star.slash" : "star") { [weak self] in
                    self?.toggleFavorite(item)
                },
            ]
        }
        if Self.canBeHidden(item) {
            actions.append(ItemAction(title: String(localized: "Hide from Search", bundle: .floe), symbol: "eye.slash") { [weak self] in
                self?.hideFromSearch(item)
            })
        }
        return actions
    }

    /// Return on the calculator's row: the answer goes to the clipboard. With no answer the row is still the
    /// selected one, so Return says what is wrong, or that there is nothing yet.
    func copyCalculation(_ result: String, error: String?) {
        guard error == nil, !result.isEmpty else {
            showHUD(error ?? String(localized: "Nothing to copy yet", bundle: .floe, comment: "Shown when Return is pressed on a calculation that has no answer."))
            return
        }
        NSPasteboard.general.copy(result)
        showHUD(String(localized: "Copied \(result)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
        hidePanel()
        reset()
    }

    /// Keeps the search that just opened something, unless the user switched that off.
    func rememberQuery() {
        if settings.remembersSearches {
            usage.recordQuery(query)
        }
    }

    /// Up at the top of the list brings back the search before this one: from an empty field the newest,
    /// and from a search brought back this way the one before it. Answers whether the key was used.
    func recallOlderQuery() -> Bool {
        guard selection == 0 else { return false }
        let queries = usage.queries
        // Typing over a search that was brought back ends the walk: the field no longer holds it.
        let held = recalledQuery.flatMap { queries.indices.contains($0) && queries[$0] == query ? $0 : nil }
        guard query.isEmpty || held != nil else { return false }
        let older = (held ?? queries.count) - 1
        guard queries.indices.contains(older) else { return held != nil }
        recalledQuery = older
        query = queries[older]
        return true
    }

    /// Takes a result out of the search. It is brought back from Settings, where it is listed by the title it had.
    func hideFromSearch(_ item: RootItem) {
        guard Self.canBeHidden(item) else { return }
        settings.hiddenResults[item.id] = item.title
        settings.favorites.removeAll { $0 == item.id }
        showHUD(String(localized: "Hidden from search. Settings › General brings it back.", bundle: .floe))
        refresh()
    }

    /// What may be hidden: a result that is there every time, and not the way into Settings, where hiding is undone.
    static func canBeHidden(_ item: RootItem) -> Bool {
        if case .settings = item {
            return false
        }
        return keepsItsPlace(item)
    }

    /// Whether a result is there the next time the launcher opens, so a favorite of it means something.
    static func keepsItsPlace(_ item: RootItem) -> Bool {
        switch item {
        case .calculator, .emoji, .searchFiles, .event, .quicklink: false
        case .file, .clipboardEntry, .menuBarItem, .menuBarAccess: false
        case .browserTab: false
        case .askAI, .webAddress, .shell, .process, .receipt, .checkpointDraft, .reminderDraft, .eventDraft: false
        default: true
        }
    }
}
