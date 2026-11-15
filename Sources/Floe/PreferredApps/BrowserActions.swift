//
//  BrowserActions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The browsers a link can go to, as its Actions menu needs them.
struct BrowserMenu {
    /// Every browser on this Mac, in the picker's order.
    let browsers: [AppOption]
    /// The one Return opens the link in; it is left out of Open With.
    let current: ResolvedApp?
    let systemDefault: ResolvedApp?

    init(choice: AppChoice?, installed: AppLookup) {
        browsers = Browsers.options(installed: installed)
        current = Browsers.current(choice: choice, installed: installed)
        systemDefault = Browsers.systemDefault(installed: installed)
    }

    /// What Return does to a web address, as its button and the first row of its menu say it.
    var openTitle: String {
        current.map { String(localized: "Open in \($0.name)", bundle: .floe, comment: "The placeholder is the name of an app.") }
            ?? String(localized: "Open", bundle: .floe, comment: "The action that opens a web address in the browser.")
    }

    /// The other browsers, each with the title its row has: the system's default says so, as a file's does.
    var others: [(title: String, url: URL)] {
        browsers.compactMap { option in
            guard let url = option.url, url.standardizedFileURL != current?.url.standardizedFileURL else { return nil }
            let isDefault = url.standardizedFileURL == systemDefault?.url.standardizedFileURL
            let title = isDefault ? String(localized: "\(option.title) (default)", bundle: .floe, comment: "The placeholder is the name of a browser.") : option.title
            return (title, url)
        }
    }
}

/// What Floe can do with a web link besides opening it where the browser role says.
enum LinkActions {
    /// The other browsers on this Mac, for one link; nil when there are none.
    static func openWith(_ url: URL, menu: BrowserMenu, host: ActionHost, opener: LinkOpener) -> ItemAction? {
        let rows = menu.others.prefix(12).map { browser in
            let icon = NSWorkspace.shared.smallIcon(forFile: browser.url.path)
            return ItemAction(title: browser.title, symbol: "app", icon: icon, id: .openWith(browser.url)) {
                opener.open(url, browser.url)
                host.dismiss()
            }
        }
        return rows.isEmpty ? nil : ItemAction(title: String(localized: "Open With", bundle: .floe), symbol: "arrow.up.forward.app", children: Array(rows), id: .openWith)
    }

    /// Copies the address that would open, scheme and all.
    static func copyAddress(_ url: URL, host: ActionHost, copy: @escaping (String) -> Void = { NSPasteboard.general.copy($0) }) -> ItemAction {
        ItemAction(title: String(localized: "Copy Address", bundle: .floe), symbol: "doc.on.doc", id: .copyAddress) {
            copy(url.absoluteString)
            host.showHUD(String(localized: "Copied Address", bundle: .floe))
        }
    }
}

extension LauncherModel {
    private var browserMenu: BrowserMenu {
        BrowserMenu(choice: settings.browserApp, installed: resolvedApps.lookup)
    }

    var openInBrowserTitle: String {
        browserMenu.openTitle
    }

    /// Opens a link of the user's: in its own app while that is installed, else a web page in the role's browser,
    /// anything else through the system.
    func openLink(_ url: URL, app: AppChoice? = nil) {
        if let message = Browsers.open(url, app: app, choice: settings.browserApp, installed: resolvedApps.lookup, opener: linkOpener) {
            panelHost.showHUD(message)
        }
    }

    /// Open With for a row that opens a web page, and Copy Address for a typed one. A quicklink to an app's own scheme gets neither.
    func linkActions(for item: RootItem) -> [ItemAction?] {
        let host = ActionHost(showHUD: { [weak self] in self?.panelHost.showHUD($0) }, dismiss: { [weak self] in
            self?.panelHost.hidePanel()
            self?.reset()
        })
        switch item {
        case let .webAddress(address):
            let openWith = LinkActions.openWith(address.url, menu: browserMenu, host: host, opener: linkOpener)
            return [openWith, LinkActions.copyAddress(address.url, host: host)].compactMap(\.self)
        case let .bookmark(bookmark):
            let openWith = LinkActions.openWith(bookmark.url, menu: browserMenu, host: host, opener: linkOpener)
            return [openWith, LinkActions.copyAddress(bookmark.url, host: host)].compactMap(\.self)
        case let .quicklink(link, queryText, _, _):
            // The selection and the clipboard are read as a link opens, not while the Actions menu is drawn.
            guard !link.fillsOnOpening, let destination = url(for: link, query: queryText), Browsers.isWebLink(destination) else { return [] }
            // The link's own browser, while it is installed, is the one Return opens and Open With leaves out.
            let own = PreferredApps.chosenApp(link.openWith, installed: resolvedApps.lookup) == nil ? nil : link.openWith
            let menu = own.map { BrowserMenu(choice: $0, installed: resolvedApps.lookup) } ?? browserMenu
            return [LinkActions.openWith(destination, menu: menu, host: host, opener: linkOpener)].compactMap(\.self)
        default:
            return []
        }
    }
}
