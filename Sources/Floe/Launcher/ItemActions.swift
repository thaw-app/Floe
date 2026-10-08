//
//  ItemActions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import SwiftUI

/// One row of an Actions menu. In a list of them, nil is a separator.
struct ItemAction {
    let title: String
    let symbol: String
    /// Drawn instead of the symbol, for a row that stands for an app.
    var icon: NSImage?
    /// A row with children opens a submenu and does nothing itself.
    var children: [ItemAction] = []
    var run: () -> Void = { /* a submenu's title */ }
}

/// What an action needs from the launcher around it.
struct ActionHost {
    let showHUD: (String) -> Void
    /// Hides the panel and returns it to the root, as opening a result does.
    let dismiss: () -> Void
    /// The roles a file can be opened in, each with its app: "Open in Ghostty".
    var preferredApps: [RoleApp] = []
    /// Keeps a receipt of something that changed the Mac.
    var record: (Receipt) -> Void = { _ in /* a host that keeps none */ }
}

enum ActionsMenu {
    static func menu(_ actions: [ItemAction?]) -> NSMenu {
        let menu = NSMenu()
        for action in actions {
            guard let action else {
                menu.addItem(.separator())
                continue
            }
            let item = ClosureMenuItem(title: action.title, handler: action.run)
            item.image = action.icon ?? NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            if !action.children.isEmpty {
                item.submenu = Self.menu(action.children)
            }
            menu.addItem(item)
        }
        return menu
    }
}

/// An empty AppKit view behind an Actions button, for NSMenu.popUp to position against. While it
/// is on screen, the model's `showActions` pops this view's menu.
struct ActionsAnchor: NSViewRepresentable {
    let model: LauncherModel
    let actions: (LauncherModel) -> [ItemAction?]

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        register(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        register(nsView)
    }

    private func register(_ view: NSView) {
        model.showActions = { [weak view, weak model, actions] in
            guard let view, let model else { return }
            let list = actions(model)
            guard !list.isEmpty else { return }
            // The panel would read the menu's tracking as losing focus and close under it.
            _ = ModalGuard.run {
                ActionsMenu.menu(list).popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 4), in: view)
            }
        }
    }
}

enum Confirm {
    /// Asks before something that cannot be taken back, and answers whether to go on.
    /// The panel is gone by then, so Floe comes forward for the question.
    static func destructive(_ question: String, detail: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = detail
        alert.addButton(withTitle: button).hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .floe))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension NSPasteboard {
    /// Replaces what is on the pasteboard with one string.
    func copy(_ text: String) {
        clearContents()
        setString(text, forType: .string)
    }
}

// MARK: - Files

/// What Floe can do with a file on disk, an application's bundle included.
enum FileActions {
    static func actions(for url: URL, host: ActionHost) -> [ItemAction?] {
        var actions: [ItemAction?] = []
        if let openWith = openWith(url, host: host) {
            actions.append(openWith)
        }
        actions += preferredAppActions(for: url, host: host)
        actions += [
            ItemAction(title: String(localized: "Show in Finder", bundle: .floe), symbol: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                host.dismiss()
            },
            nil,
        ]
        actions += copies(of: url, host: host)
        if canTrash(url) {
            actions += [nil, trashAction(url, host: host)]
        }
        return actions
    }

    static func trashAction(_ url: URL, host: ActionHost) -> ItemAction {
        ItemAction(title: String(localized: "Move to Trash…", bundle: .floe), symbol: "trash") { trash(url, host: host) }
    }

    /// An app is not copied as a file, so its menu leaves that row out.
    static func copies(of url: URL, host: ActionHost, includesFile: Bool = true) -> [ItemAction] {
        let name = FileManager.default.displayName(atPath: url.path)
        let copies = [
            ItemAction(title: String(localized: "Copy Path", bundle: .floe), symbol: "doc.on.doc") {
                NSPasteboard.general.copy(url.path)
                host.showHUD(String(localized: "Copied Path", bundle: .floe))
            },
            ItemAction(title: String(localized: "Copy Name", bundle: .floe), symbol: "textformat") {
                NSPasteboard.general.copy(name)
                host.showHUD(String(localized: "Copied \(name)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            },
            ItemAction(title: String(localized: "Copy File", bundle: .floe), symbol: "doc.on.clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                host.showHUD(String(localized: "Copied \(name)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            },
        ]
        return includesFile ? copies : Array(copies.dropLast())
    }

    /// The apps that can open the file, the one that opens it by default first; nil when there are none.
    private static func openWith(_ url: URL, host: ActionHost) -> ItemAction? {
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: url)
        let apps = orderedApps(workspace.urlsForApplications(toOpen: url), preferred: preferred)
        guard !apps.isEmpty else { return nil }
        let rows = apps.prefix(12).map { app in
            let icon = workspace.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            return ItemAction(title: app == preferred ? String(localized: "\(name) (default)", bundle: .floe, comment: "A row in the Open With menu. The placeholder is the name of the app that opens this kind of file by default.") : name, symbol: "app", icon: icon) {
                workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                host.dismiss()
            }
        }
        return ItemAction(title: String(localized: "Open With", bundle: .floe, comment: "The title of a submenu that lists apps."), symbol: "arrow.up.forward.app", children: Array(rows))
    }

    /// The default app first, then the rest by name, one row per app.
    static func orderedApps(_ apps: [URL], preferred: URL?) -> [URL] {
        let rest = apps.uniqued(on: \.standardizedFileURL.path)
            .filter { $0.standardizedFileURL != preferred?.standardizedFileURL }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        return (preferred.map { [$0] } ?? []) + rest
    }

    /// Nothing under /System can be moved, so the row is left out there instead of failing.
    static func canTrash(_ url: URL) -> Bool {
        !url.standardizedFileURL.path.hasPrefix("/System/") && FileManager.default.isDeletableFile(atPath: url.path)
    }

    /// The panel goes away before the question, like a system command that asks first.
    private static func trash(_ url: URL, host: ActionHost) {
        let name = FileManager.default.displayName(atPath: url.path)
        host.dismiss()
        let detail = String(localized: "You can put it back from the Trash until you empty it.", bundle: .floe)
        guard Confirm.destructive(String(localized: "Move “\(name)” to the Trash?", bundle: .floe, comment: "The placeholder is a file name."), detail: detail, button: String(localized: "Move to Trash", bundle: .floe)) else { return }
        do {
            try host.record(ReceiptStore.trash(url))
            host.showHUD(String(localized: "Moved to Trash", bundle: .floe))
        } catch {
            host.showHUD(String(localized: "Couldn't move \(name) to the Trash", bundle: .floe, comment: "The placeholder is a file name."))
        }
    }
}

// MARK: - Applications

/// What Floe can do with an application besides opening it.
enum AppActions {
    static func running(_ app: AppEntry) -> NSRunningApplication? {
        let target = app.url.standardizedFileURL
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == target }
    }

    static func actions(for app: AppEntry, host: ActionHost) -> [ItemAction?] {
        var actions: [ItemAction?] = []
        if let running = running(app) {
            actions += processActions(app, running, host: host) + [nil]
        }
        actions += [
            ItemAction(title: String(localized: "Show in Finder", bundle: .floe), symbol: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
                host.dismiss()
            },
            nil,
        ]
        actions += FileActions.copies(of: app.url, host: host, includesFile: false)
        if let identifier = Bundle(url: app.url)?.bundleIdentifier {
            actions.append(ItemAction(title: String(localized: "Copy Bundle Identifier", bundle: .floe), symbol: "number") {
                NSPasteboard.general.copy(identifier)
                host.showHUD(String(localized: "Copied \(identifier)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            })
        }
        // A running app is quit first: the Trash refuses a bundle that is in use.
        if running(app) == nil, FileActions.canTrash(app.url) {
            actions += [nil, FileActions.trashAction(app.url, host: host)]
        }
        return actions
    }

    private static func processActions(_ app: AppEntry, _ running: NSRunningApplication, host: ActionHost) -> [ItemAction] {
        var actions: [ItemAction] = []
        if !running.isHidden {
            actions.append(ItemAction(title: String(localized: "Hide", bundle: .floe, comment: "An action that hides a running app's windows."), symbol: "eye.slash") {
                running.hide()
                host.dismiss()
            })
        }
        actions.append(ItemAction(title: String(localized: "Quit", bundle: .floe, comment: "An action that quits a running app."), symbol: "xmark.circle") {
            running.terminate()
            host.showHUD(String(localized: "Quitting \(app.name)", bundle: .floe, comment: "The placeholder is an app's name."))
        })
        actions.append(ItemAction(title: String(localized: "Restart", bundle: .floe, comment: "An action that quits a running app and opens it again."), symbol: "arrow.clockwise") {
            restart(app, running, host: host)
        })
        actions.append(ItemAction(title: String(localized: "Force Quit…", bundle: .floe), symbol: "xmark.octagon") { forceQuit(app, running, host: host) })
        return actions
    }

    private static func restart(_ app: AppEntry, _ running: NSRunningApplication, host: ActionHost) {
        running.terminate()
        host.showHUD(String(localized: "Restarting \(app.name)", bundle: .floe, comment: "The placeholder is an app's name."))
        Task { @MainActor in
            // An app asked to quit may stop to ask about unsaved work. It is opened again once it has gone,
            // and left alone when it is still there after ten seconds: the user is answering it, or said no.
            for _ in 0 ..< 100 where !running.isTerminated {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard running.isTerminated else {
                host.showHUD(String(localized: "\(app.name) is still running, so it was not restarted", bundle: .floe, comment: "The placeholder is an app's name."))
                return
            }
            _ = try? await NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func forceQuit(_ app: AppEntry, _ running: NSRunningApplication, host: ActionHost) {
        host.dismiss()
        let detail = String(localized: "You will lose any changes you haven't saved.", bundle: .floe)
        guard Confirm.destructive(String(localized: "Force “\(app.name)” to quit?", bundle: .floe, comment: "The placeholder is an app's name."), detail: detail, button: String(localized: "Force Quit", bundle: .floe)) else { return }
        running.forceTerminate()
        host.showHUD(String(localized: "Forced \(app.name) to quit", bundle: .floe, comment: "The placeholder is an app's name."))
    }
}
