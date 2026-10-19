//
//  RootIcon.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

struct RootIcon: View {
    let item: RootItem
    var body: some View {
        switch item {
        case let .app(app):
            AppIconView(path: app.url.path, size: 24)
        case let .command(command):
            IconView(value: command.icon ?? "icon:Terminal", assetsPath: command.assetsPath, size: 24)
        case let .script(script):
            IconView(value: script.icon ?? "icon:Terminal", assetsPath: "", size: 24)
        case .menuBarSearch:
            IconView(value: "icon:MenubarRectangle", assetsPath: "", size: 24)
        case .menuItemSearch:
            SymbolTile(symbol: "filemenu.and.selection")
        case .emojiSearch:
            Text(verbatim: "😀").font(.system(size: 20))
        case .clipboardHistory:
            IconView(value: "icon:Clipboard", assetsPath: "", size: 24)
        case .noteDesk:
            SymbolTile(symbol: "note.text")
        case .floatingNote:
            SymbolTile(symbol: "note.text.badge.plus")
        case let .clipboardApp(destination):
            // The chosen app's icon says where the command goes; one that is gone keeps the clipboard.
            if let app = destination.app {
                AppIconView(path: app.url.path, size: 24)
            } else {
                IconView(value: "icon:Clipboard", assetsPath: "", size: 24)
            }
        case .fileSearch, .searchFiles:
            IconView(value: "icon:Document", assetsPath: "", size: 24)
        case .settings:
            IconView(value: "icon:Gear", assetsPath: "", size: 24)
        case .thaw:
            // Thaw's own icon, so its rows read as that app's and not as one more system command.
            AppIconView(path: Thaw.applicationURL?.path ?? "", size: 24)
        case let .finderSelection(_, app):
            AppIconView(path: app.url.path, size: 24)
        case let .settingsPane(pane):
            // The icon System Settings shows for the pane, where macOS has one.
            if let path = pane.iconPath {
                AppIconView(path: path, size: 24)
            } else {
                SymbolTile(symbol: pane.symbol)
            }
        case .calculator:
            IconView(value: "icon:Calculator", assetsPath: "", size: 24)
        case let .emoji(entry):
            Text(entry.character).font(.system(size: 20))
        case let .quicklink(link, _, _, _):
            Image(systemName: link.symbol)
                .font(.system(size: 24 * 0.55))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 24 * 0.22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24 * 0.22, style: .continuous))
        case let .file(file):
            AppIconView(path: file.url.path, size: 24)
        case let .browserTab(row):
            // The browser's icon says where the tab is; a browser that refused shows the raised hand.
            if case .tab = row, let path = row.browser.applicationURL?.path {
                AppIconView(path: path, size: 24)
            } else {
                SymbolTile(symbol: "hand.raised")
            }
        case let .menuBarItem(extra, _):
            if let owner = extra.ownerURL {
                AppIconView(path: owner.path, size: 24)
            } else {
                SymbolTile(symbol: "menubar.rectangle")
            }
        case let .process(process):
            if let bundle = process.bundlePath {
                AppIconView(path: bundle, size: 24)
            } else {
                SymbolTile(symbol: "gearshape.2")
            }
        case let .sshHost(_, terminal):
            // The terminal's icon says where the connection opens.
            if let terminal {
                AppIconView(path: terminal.url.path, size: 24)
            } else {
                SymbolTile(symbol: "terminal")
            }
        case .shortcut:
            AppleShortcutIcon()
        case let .window(.window(window)):
            if let url = window.appURL {
                AppIconView(path: url.path, size: 24)
            } else {
                SymbolTile(symbol: "macwindow")
            }
        case .window(.access), .menuItem(.access):
            SymbolTile(symbol: "hand.raised")
        case let .menuItem(.item(_, target)):
            // The app's icon says whose menus the command is in.
            if let url = target.url {
                AppIconView(path: url.path, size: 24)
            } else {
                SymbolTile(symbol: "filemenu.and.selection")
            }
        case .extensionStore, .system, .note, .snippet, .event, .clipboardEntry,
             .menuBarAccess, .askAI, .webAddress, .checkpoint, .checkpointDraft,
             .reminderDraft, .eventDraft, .contact, .outgoing, .focus, .keyword,
             .definition, .answer, .bookmark, .brew, .soundDevice, .qrCode, .place, .timer, .receipt, .shell:
            symbolIcon
        }
    }

    /// The exhaustive outer switch sends only symbol-backed rows here.
    @ViewBuilder private var symbolIcon: some View {
        switch item {
        case .extensionStore:
            SymbolTile(symbol: "bag")
        case let .system(command):
            SymbolTile(symbol: command.symbol)
        case let .note(action, _):
            SymbolTile(symbol: action.symbol)
        case .snippet:
            SymbolTile(symbol: "text.quote", tint: .teal)
        case .event:
            SymbolTile(symbol: "calendar", tint: .red)
        case let .clipboardEntry(entry):
            SymbolTile(symbol: entry.kind.symbol)
        case .menuBarAccess:
            SymbolTile(symbol: "hand.raised")
        case .askAI:
            SymbolTile(symbol: AskAI.symbol)
        case .webAddress:
            SymbolTile(symbol: "globe")
        case .checkpoint:
            SymbolTile(symbol: "bookmark")
        case .checkpointDraft:
            SymbolTile(symbol: "bookmark.fill")
        case .reminderDraft:
            SymbolTile(symbol: "bell")
        case .eventDraft:
            SymbolTile(symbol: "calendar.badge.plus", tint: .red)
        case let .contact(row):
            SymbolTile(symbol: row == .access ? "hand.raised" : "person.crop.circle")
        case let .outgoing(draft):
            SymbolTile(symbol: draft.kind == .mail ? "envelope" : "message")
        case .focus:
            SymbolTile(symbol: "moon")
        case .keyword:
            SymbolTile(symbol: "character.cursor.ibeam")
        case .definition:
            SymbolTile(symbol: "character.book.closed")
        case let .answer(row):
            SymbolTile(symbol: row.symbol)
        case .bookmark:
            SymbolTile(symbol: "book")
        case let .brew(package):
            SymbolTile(symbol: package.isCask ? "macwindow" : "shippingbox")
        case let .soundDevice(row):
            SymbolTile(symbol: row.symbol)
        case .qrCode:
            SymbolTile(symbol: "qrcode")
        case .place:
            SymbolTile(symbol: "mappin.and.ellipse")
        case .timer:
            SymbolTile(symbol: "timer")
        case let .receipt(receipt):
            SymbolTile(symbol: receipt.canUndo ? "arrow.uturn.backward" : "list.bullet.clipboard")
        case let .shell(row, _):
            SymbolTile(symbol: row.origin.symbol)
        default:
            EmptyView()
        }
    }
}

/// A symbol on the rounded tile the built-in results use where an app has its icon.
struct SymbolTile: View {
    let symbol: String
    var tint = Color.primary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 24 * 0.22, style: .continuous))
    }
}
