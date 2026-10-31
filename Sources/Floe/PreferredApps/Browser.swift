//
//  Browser.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

/// Opens a link: in one app when it is named, through the system when it is not.
/// Tests pass their own, so nothing is opened.
struct LinkOpener: Sendable {
    var open: @Sendable (URL, URL?) -> Void

    static let system = LinkOpener { url, application in
        if let application {
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.openWithoutWaiting(url)
        }
    }
}

/// Where a link opens.
enum LinkDestination: Equatable, Sendable {
    /// Through the system: the role is on Default Browser, or the link is not a web page.
    case system
    case browser(ResolvedApp)
    /// The chosen browser is gone, by name. The link still opens, through the system.
    case systemInstead(of: String)
}

/// The browser role: which app web links open in. Everything but `onThisMac` and `openFromFloe` only decides.
enum Browsers {
    /// Web pages to ask the system about. They are never opened.
    private static let securePage = URL(string: "https://example.com")
    private static let plainPage = URL(string: "http://example.com")

    /// Only these go to a browser: `mailto:`, `raycast://` and every app's own scheme stay with the system.
    static func isWebLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }

    /// The app macOS opens web links with.
    static func systemDefault(installed: AppLookup) -> ResolvedApp? {
        securePage.flatMap(installed.appForURL).map(ResolvedApp.init)
    }

    /// The browsers the system lists right now. Nothing is kept: an app installed a minute ago is there.
    static func onThisMac() -> [URL] {
        guard let securePage, let plainPage else { return [] }
        let workspace = NSWorkspace.shared
        let found = browsers(
            secure: workspace.urlsForApplications(toOpen: securePage),
            plain: workspace.urlsForApplications(toOpen: plainPage),
            pages: workspace.urlsForApplications(toOpen: UTType.html)
        )
        return withoutLinkHandlers(found) { Bundle(url: $0)?.bundleIdentifier }
    }

    /// Apps that take web links and are not browsers, by the identifier read from an installed copy.
    /// ChatGPT is here by name so it stays out even if it comes to open HTML files as well.
    static let linkHandlers: Set<String> = ["com.openai.codex"]

    static func withoutLinkHandlers(_ apps: [URL], identifier: (URL) -> String?) -> [URL] {
        apps.filter { app in identifier(app).map { !linkHandlers.contains($0) } ?? true }
    }

    /// A browser opens `https` links, `http` links and HTML files. An app that takes links alone
    /// (a chat app that claims `https`) is not listed, and is still picked with Choose.
    static func browsers(secure: [URL], plain: [URL], pages: [URL]) -> [URL] {
        let others = [plain, pages].map { Set($0.map(\.standardizedFileURL.path)) }
        return secure.filter { app in others.allSatisfy { $0.contains(app.standardizedFileURL.path) } }
    }

    /// The picker's rows for the browsers: the default one first, the rest by name, one row per app.
    static func options(installed: AppLookup) -> [AppOption] {
        let found = installed.browsers()
        let standard = systemDefault(installed: installed)?.url.standardizedFileURL
        let first = found.first { $0.standardizedFileURL == standard }
        let rows = FileActions.orderedApps(found, preferred: first).map { url in
            AppOption(choice: PreferredApps.choice(forAppAt: url, installed: installed), title: ResolvedApp(url: url).name, url: url)
        }
        return Array(rows.uniqued(on: \.id))
    }

    /// The browser a web link opens in right now: the chosen one while it is installed, else the default.
    static func current(choice: AppChoice?, installed: AppLookup) -> ResolvedApp? {
        PreferredApps.app(for: .browser, choice: choice, installed: installed)
    }

    static func destination(for url: URL, choice: AppChoice?, installed: AppLookup) -> LinkDestination {
        guard isWebLink(url), let choice else { return .system }
        if let app = PreferredApps.chosenApp(choice, installed: installed) {
            return .browser(app)
        }
        return .systemInstead(of: ResolvedApp(url: URL(fileURLWithPath: choice.path)).name)
    }

    /// Opens a link where the role says. Answers the line to show when the chosen browser was
    /// missing: the link has opened all the same, so nothing is lost by a browser being removed.
    static func open(_ url: URL, choice: AppChoice?, installed: AppLookup, opener: LinkOpener) -> String? {
        switch destination(for: url, choice: choice, installed: installed) {
        case .system:
            opener.open(url, nil)
            return nil
        case let .browser(app):
            opener.open(url, app.url)
            return nil
        case let .systemInstead(missing):
            opener.open(url, nil)
            guard let standIn = systemDefault(installed: installed)?.name else {
                return String(localized: "\(missing) isn't installed. Opened in the default browser", bundle: .floe, comment: "The placeholder is the name of a browser.")
            }
            return String(localized: "\(missing) isn't installed. Opened in \(standIn)", bundle: .floe, comment: "Both placeholders are names of browsers.")
        }
    }

    /// A link clicked in one of Floe's views. False leaves it to the system, exactly as before the role existed.
    static func openFromView(_ url: URL, choice: AppChoice?, installed: AppLookup, opener: LinkOpener, notify: (String) -> Void) -> Bool {
        guard destination(for: url, choice: choice, installed: installed) != .system else { return false }
        if let message = open(url, choice: choice, installed: installed, opener: opener) {
            notify(message)
        }
        return true
    }

    /// For a link Floe opens with no launcher or view around it, like an extension's sign-in page.
    @MainActor
    static func openFromFloe(_ url: URL, say: (String) -> Void) {
        if let message = open(url, choice: AppSettings.shared.browserApp, installed: .system, opener: .system) {
            say(message)
        }
    }
}

extension View {
    /// Links clicked anywhere inside open where the browser role says: About, What's New, the store, an extension's view.
    func openingLinksInTheChosenBrowser(settings: AppSettings = .shared) -> some View {
        environment(\.openURL, OpenURLAction { url in
            let opened = Browsers.openFromView(url, choice: settings.browserApp, installed: .system, opener: .system) {
                ThawHUD.show(text: $0)
            }
            return opened ? .handled : .systemAction
        })
    }
}

extension SearchIndex {
    /// The browser role's picker on the Applications page.
    static let browserEntries: [SearchEntry] = [
        .on(
            .applications,
            "browserApp",
            AppRole.browser.title,
            description: AppRole.browser.detail,
            section: String(localized: "Preferred Apps", bundle: .floe),
            keywords: String(
                localized: "browser, web browser, default browser, web, links, web address, quicklink, preferred app, default app",
                bundle: .floe,
                comment: "Words that find the Browser setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]
}
