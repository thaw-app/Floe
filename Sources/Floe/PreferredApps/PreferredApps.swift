//
//  PreferredApps.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import UniformTypeIdentifiers

/// What Floe asks about the apps on this Mac. Tests pass their own answers.
struct AppLookup {
    /// Where the app with a bundle identifier is, if it is installed.
    var url: (String) -> URL?
    /// The app macOS opens plain text files with.
    var plainTextApp: () -> URL?
    var exists: (URL) -> Bool
    var bundleIdentifier: (URL) -> String?
    /// The app that answers a link, if any does.
    var appForURL: (URL) -> URL? = { _ in nil }
    /// The browsers on this Mac, as the system lists them now.
    var browsers: () -> [URL] = { [] }

    static let system = AppLookup(
        url: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        plainTextApp: { NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText) },
        exists: { FileManager.default.fileExists(atPath: $0.path) },
        bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier },
        appForURL: { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        browsers: { Browsers.onThisMac() }
    )
}

/// One row of a role's picker. Without a choice it is the role's default.
struct AppOption: Identifiable, Equatable {
    static let defaultID = "default"

    let choice: AppChoice?
    let title: String
    /// Where the app is, for its icon; nil when it is not on this Mac.
    let url: URL?

    var id: String {
        choice?.key ?? Self.defaultID
    }
}

/// What to open and the app to open it with.
nonisolated struct Handoff: Equatable {
    let urls: [URL]
    let application: URL
}

/// Which app a role stands for, and what it is handed. Everything but `open` only decides.
enum PreferredApps {
    /// The chosen app when it is still on this Mac, else what the role uses when nothing is chosen.
    static func app(for role: AppRole, choice: AppChoice?, installed: AppLookup) -> ResolvedApp? {
        chosenApp(choice, installed: installed) ?? fallback(for: role, installed: installed)
    }

    /// The app behind a choice: by bundle identifier first, so one that moved is still found.
    static func chosenApp(_ choice: AppChoice?, installed: AppLookup) -> ResolvedApp? {
        guard let choice else { return nil }
        if let found = choice.bundleIdentifier.flatMap(installed.url) {
            return ResolvedApp(url: found)
        }
        let picked = URL(fileURLWithPath: choice.path)
        return installed.exists(picked) ? ResolvedApp(url: picked) : nil
    }

    /// Nothing chosen: the terminal is the system's Terminal, the editor whatever opens plain text files.
    /// Notes has no app to open things with: its setting always names one, starting at Apple Notes.
    static func fallback(for role: AppRole, installed: AppLookup) -> ResolvedApp? {
        switch role {
        case .terminal: installed.url(AppRole.systemTerminal).map(ResolvedApp.init)
        case .editor: installed.plainTextApp().map(ResolvedApp.init)
        case .browser: Browsers.systemDefault(installed: installed)
        case .notes, .clipboard: nil
        }
    }

    /// Every role that opens files, with the app it resolves to now. A role without one is left out.
    static func apps(choice: (AppRole) -> AppChoice?, installed: AppLookup) -> [RoleApp] {
        AppRole.opening.compactMap { role in
            app(for: role, choice: choice(role), installed: installed).map { RoleApp(role: role, app: $0) }
        }
    }

    /// The choice that stands for an app picked by hand.
    static func choice(forAppAt url: URL, installed: AppLookup) -> AppChoice {
        AppChoice(bundleIdentifier: installed.bundleIdentifier(url), path: url.path)
    }

    /// A role's picker: its default, the known apps that are installed, and the chosen app when it is none of those.
    static func options(for role: AppRole, choice: AppChoice?, installed: AppLookup) -> [AppOption] {
        let standIn = fallback(for: role, installed: installed)
        var options = [AppOption(choice: nil, title: role.defaultTitle(appName: standIn?.name), url: standIn?.url)]
        options += role.knownApps.compactMap { identifier in
            installed.url(identifier).map { url in
                AppOption(choice: AppChoice(bundleIdentifier: identifier, path: url.path), title: ResolvedApp(url: url).name, url: url)
            }
        }
        options += role == .browser ? Browsers.options(installed: installed) : []
        guard let choice, !options.contains(where: { $0.id == choice.key }) else { return options }
        if let app = chosenApp(choice, installed: installed) {
            options.append(AppOption(choice: choice, title: app.name, url: app.url))
        } else {
            let name = ResolvedApp(url: URL(fileURLWithPath: choice.path)).name
            options.append(AppOption(choice: choice, title: String(localized: "\(name) (not installed)", bundle: .floe, comment: "The placeholder is the name of an app."), url: nil))
        }
        return options
    }

    /// What the role's app is handed for some items: a terminal gets folders, so a file becomes the
    /// folder it is in. Nil when there is nothing to hand over.
    static func handoff(_ items: [URL], to app: ResolvedApp, role: AppRole, isFolder: (URL) -> Bool) -> Handoff? {
        let urls: [URL] = switch role.input {
        case .folder: items.map { isFolder($0) ? $0 : $0.deletingLastPathComponent() }
        case .fileOrFolder: items
        case .text, .nothing, .link: []
        }
        let distinct = Array(urls.uniqued(on: \.standardizedFileURL.path))
        return distinct.isEmpty ? nil : Handoff(urls: distinct, application: app.url)
    }

    /// A folder to work in. A package is a folder on disk but stands for one thing, like a file.
    static nonisolated func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    static func open(_ handoff: Handoff) {
        NSWorkspace.shared.open(handoff.urls, withApplicationAt: handoff.application, configuration: NSWorkspace.OpenConfiguration())
    }
}

extension AppSettings {
    /// The app chosen for a role; nil is the role's default. The notes role's choice is `notesApp`.
    func appChoice(for role: AppRole) -> AppChoice? {
        switch role {
        case .terminal: terminalApp
        case .editor: editorApp
        case .browser: browserApp
        case .notes: nil
        case .clipboard: clipboardHandler == .app ? clipboardApp : nil
        }
    }
}
