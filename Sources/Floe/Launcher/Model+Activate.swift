//
//  Model+Activate.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Opening a root result.
extension LauncherModel {
    /// Executes the selected root result, including routing Settings rows to their requested page. The keys held
    /// reach the emoji and shell rows, which give them a meaning.
    func activate(_ item: RootItem, flags: NSEvent.ModifierFlags = []) {
        // An emoji keeps its own count of uses and remembers no query.
        if features.emoji.open(item, flags: flags) {
            return
        }
        if item.isScopeResult {
            // Found just now and gone next time: opening one records no frecency entry.
            (scopeResultOpener ?? openScopeResult)(item)
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
            if let destination = url(for: link, query: queryText) {
                openLink(destination)
            }
            panelHost.hidePanel()
            reset()
        case let .finderSelection(role, app):
            openFinderSelection(in: role, app: app)
        case let .snippet(snippet):
            runner.paste(text: SnippetStore.shared.expanded(snippet))
        default:
            break
        }
    }
}
