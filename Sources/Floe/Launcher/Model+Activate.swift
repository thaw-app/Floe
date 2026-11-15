//
//  Model+Activate.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Opening a root result.
extension LauncherModel {
    /// Return on a result: the default the user chose for it, or else what Floe does.
    func activate(_ item: RootItem, flags: NSEvent.ModifierFlags = []) {
        if features.actions.open(item, flags: flags) {
            return
        }
        openAsFloeDoes(item, flags: flags)
    }

    /// Executes the selected root result, including routing Settings rows to their requested page. The keys held
    /// reach the emoji and shell rows, which give them a meaning.
    func openAsFloeDoes(_ item: RootItem, flags: NSEvent.ModifierFlags = []) {
        // An emoji keeps its own count of uses and remembers no query.
        if features.emoji.open(item, flags: flags) {
            return
        }
        if item.isScopeResult {
            // Found just now and gone next time: opening one records no frecency entry.
            (scopeResultOpener ?? { self.openScopeResult($0, flags: flags) })(item)
            return
        }
        if case let .askAI(question) = item {
            // Nothing about a question is kept: no usage record either.
            openAskAI(question)
            return
        }
        if case .searchFiles = item {
            // A transient row for the query text: opening it records no frecency entry.
        } else {
            usage.recordUse(of: item.id)
        }
        rememberQuery()
        if openByOwner(item, flags: flags) {
            return
        }
        switch item {
        case let .app(app):
            NSWorkspace.shared.openWithoutWaiting(app.url)
            panelHost.hidePanel()
            reset()
        case let .command(command):
            runner.run(command)
        case let .fallbackCommand(command, text):
            runner.run(command, arguments: Fallback.arguments(for: command, text: text), fallbackText: text)
        case .menuBarSearch:
            openMenuBarSearch()
        case .emojiSearch:
            query = EmojiSearchProvider.prefix
            focusToken += 1
        case .clipboardHistory, .clipboardApp:
            openClipboardHistory()
        case .fileSearch:
            openFileSearch(with: query)
        case let .searchFiles(searchQuery):
            openFileSearch(with: searchQuery)
        case .noteDesk:
            openNoteDesk()
        case .settings, .extensionStore:
            panelHost.hidePanel()
            panelHost.openSettings(item.settingsPage)
        case let .quicklink(link, queryText, _, _):
            openQuicklink(link, query: queryText)
        case let .finderSelection(role, app):
            openFinderSelection(in: role, app: app)
        case let .snippet(snippet):
            runner.paste(text: SnippetStore.shared.expanded(snippet))
        default:
            break
        }
    }

    private func openQuicklink(_ link: Quicklink, query: String) {
        guard link.fillsOnOpening else {
            if let destination = url(for: link, query: query) {
                openLink(destination, app: link.openWith)
            }
            panelHost.hidePanel()
            reset()
            return
        }
        // The panel goes first, so a Command-C borrowed for the selection reaches the app behind it.
        panelHost.hidePanel()
        reset()
        Task { await openFilled(link, query: query) }
    }

    /// Opens a link with its {selection} and {clipboard} read now. Without a selection to fill it opens nothing and says why.
    func openFilled(_ link: Quicklink, query: String) async {
        var fills = QuicklinkFills()
        if link.url.contains("{clipboard}") {
            fills.clipboard = quicklinkFills.clipboard()
        }
        if link.url.contains("{selection}") {
            do {
                fills.selection = try await quicklinkFills.selection()
            } catch SelectionError.accessibilityOff {
                panelHost.showHUD(SelectionError.accessibilityOff.localizedDescription)
                return
            } catch {
                panelHost.showHUD(String(localized: "No text is selected.", bundle: .floe, comment: "A quicklink that fills in the selected text found none."))
                return
            }
        }
        if let destination = url(for: link, query: query, fills: fills) {
            openLink(destination, app: link.openWith)
        }
    }
}
