//
//  MenuItems.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The app whose menus are searched: the one in front when the launcher opened.
nonisolated struct MenuTarget: Sendable, Equatable {
    let pid: pid_t
    let name: String
    let url: URL?
}

/// A row of `menus`: a command of the front app, or the row that stands in for them until Floe may read them.
nonisolated enum MenuItemRow: Sendable {
    case item(AppMenuItem, in: MenuTarget)
    case access
}

extension AppMenuItem: Identifiable {
    nonisolated var id: String {
        pathKey
    }

    /// The menus the item sits in, such as File > Export, without the item itself.
    nonisolated var menuPath: String {
        path.dropLast().joined(separator: " > ")
    }
}

/// Finds the front app's menu commands with CMD-Z's scanner and chooses one.
enum MenuItems {
    static let keyword = "menus"

    /// The app in front, unless it is Floe: the panel never makes its own process active, so while it is
    /// on screen this is still the app the user came from.
    static func frontApp() -> MenuTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return MenuTarget(pid: app.processIdentifier, name: app.localizedName ?? "", url: app.bundleURL)
    }

    /// The commands that can be chosen whose title or menus match, best first. Without a query, all of them in menu order.
    nonisolated static func ranked(_ entries: [AppMenuItem], query: String) -> [AppMenuItem] {
        let enabled = entries.filter(\.enabled)
        guard !query.isEmpty else { return enabled }
        return enabled.ranked { Ranking.menuBarScore(query: query, name: $0.title, owner: $0.menuPath) }
    }

    /// Brings the app forward, so the command acts on its window, then presses the item off the main thread.
    static func choose(_ entry: AppMenuItem, in target: MenuTarget) {
        NSRunningApplication(processIdentifier: target.pid)?.activate()
        let path = entry.path
        let indices = entry.indices
        DispatchQueue.global(qos: .userInitiated).async {
            _ = MenuSearchScanner.trigger(path: path, indices: indices, pid: target.pid)
        }
    }
}
