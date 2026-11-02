//
//  SessionApps.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The apps open now, as a checkpoint lists them, puts them away and brings them back.
enum SessionApps {
    /// Stays open when the others quit: macOS keeps it running.
    private static let finder = "com.apple.finder"

    /// The apps with windows and a Dock icon other than Floe, the app in front last.
    static var others: [NSRunningApplication] {
        let workspace = NSWorkspace.shared
        let me = ProcessInfo.processInfo.processIdentifier
        let myself = Bundle.main.bundleIdentifier
        let front = workspace.frontmostApplication?.processIdentifier
        let apps = workspace.runningApplications.filter { app in
            app.activationPolicy == .regular && app.processIdentifier != me && (myself == nil || app.bundleIdentifier != myself)
        }
        return apps.filter { $0.processIdentifier != front } + apps.filter { $0.processIdentifier == front }
    }

    static func items() -> [Checkpoint.Item] {
        others.compactMap { app in
            app.bundleURL.map { url in
                Checkpoint.Item(kind: .app, value: url.path, title: app.localizedName ?? url.deletingPathExtension().lastPathComponent)
            }
        }
    }

    /// Hides the apps a checkpoint listed. One opened since then was not saved, so it is left alone.
    static func hide(_ listed: [Checkpoint.Item]) {
        let paths = Set(listed.map(\.value))
        for app in others where app.bundleURL.map({ paths.contains($0.path) }) == true {
            app.hide()
        }
    }

    /// Asks the apps a checkpoint listed to quit. One opened since then was not saved, so it stays open.
    static func quit(_ listed: [Checkpoint.Item]) {
        let paths = Set(listed.map(\.value))
        for app in others where app.bundleIdentifier != finder && app.bundleURL.map({ paths.contains($0.path) }) == true {
            app.terminate()
        }
    }

    /// Asks each app to quit. One with unsaved work may stop to ask, and stays open if the user says no.
    static func quit() {
        for app in others where app.bundleIdentifier != finder {
            app.terminate()
        }
    }

    /// Whether the app at a path is a browser Floe can ask about its tabs, and is not running.
    static func isStoppedBrowser(_ url: URL) -> Bool {
        let wanted = url.standardizedFileURL
        guard let identifier = Bundle(url: wanted)?.bundleIdentifier, BrowserApp.all.contains(where: { $0.bundleID == identifier }) else { return false }
        return !NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == wanted }
    }

    /// Shows an app that is running, by where it is rather than its name, and opens one that is not.
    static func bringBack(_ url: URL, activates: Bool) {
        let wanted = url.standardizedFileURL
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL == wanted }) {
            running.unhide()
            if activates {
                running.activate()
            }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: wanted, configuration: configuration)
    }
}
