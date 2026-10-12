//
//  BrowserTabs.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// A browser that lists its open tabs through AppleScript. Only terms read from the browser's own
/// scripting definition (`sdef`) belong here; a browser without tabs in its definition has no entry.
nonisolated struct BrowserApp: Equatable, Sendable {
    /// What a tab is found again by when it is brought forward.
    enum TabKey: Sendable {
        /// The tab's place in its window; the address is checked in case the tabs moved.
        case position
        /// The `id` the browser gives each tab.
        case id
    }

    let name: String
    let bundleID: String
    /// The property that holds a tab's title.
    let titleTerm: String
    let tabKey: TabKey
    /// What brings `tab floeIndex of floeWindow` forward. Reordering the windows comes last:
    /// `floeWindow` is a window by position.
    let select: [String]

    static let safari = BrowserApp(
        name: "Safari",
        bundleID: "com.apple.Safari",
        titleTerm: "name",
        tabKey: .position,
        select: [
            "set current tab of floeWindow to tab floeIndex of floeWindow",
            "if miniaturized of floeWindow then set miniaturized of floeWindow to false",
            "set index of floeWindow to 1",
        ]
    )
    static let dia = BrowserApp(
        name: "Dia",
        bundleID: "company.thebrowser.dia",
        titleTerm: "title",
        tabKey: .id,
        select: ["focus tab floeIndex of floeWindow"]
    )
    /// Helium has Chromium's scripting suite.
    static let helium = BrowserApp(
        name: "Helium",
        bundleID: "net.imput.helium",
        titleTerm: "title",
        tabKey: .id,
        select: [
            "set active tab index of floeWindow to floeIndex",
            "if minimized of floeWindow then set minimized of floeWindow to false",
            "set index of floeWindow to 1",
        ]
    )
    static let all = [safari, dia, helium]

    /// Read without scripting, so asking never launches the browser or needs a permission.
    static func isRunning(_ browser: BrowserApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

nonisolated struct BrowserTab: Equatable, Sendable {
    let browser: BrowserApp
    /// The window's `id`, as text.
    let window: String
    /// The tab's place in its window or its `id`, as the browser's `tabKey` says.
    let key: String
    let title: String
    let url: String

    /// The site, which tells two tabs with one title apart.
    var host: String? {
        guard let host = URL(string: url)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A row of the tabs source.
enum BrowserTabRow: Equatable {
    case tab(BrowserTab)
    /// Stands in for a browser's tabs after macOS refused to let Floe ask for them.
    case access(BrowserApp)

    var id: String {
        switch self {
        case let .tab(tab): "browser-tab:\(tab.browser.bundleID)|\(tab.window)|\(tab.key)"
        case let .access(browser): "browser-access:\(browser.bundleID)"
        }
    }

    var title: String {
        switch self {
        case let .tab(tab): tab.title.isEmpty ? tab.url : tab.title
        case let .access(browser): String(localized: "Floe needs permission to list \(browser.name)'s tabs", bundle: .floe, comment: "The placeholder is the name of a browser.")
        }
    }

    var label: String {
        switch self {
        case let .tab(tab): tab.host ?? tab.browser.name
        case let .access(browser): browser.name
        }
    }

    var browser: BrowserApp {
        switch self {
        case let .tab(tab): tab.browser
        case let .access(browser): browser
        }
    }
}

/// The scripts that list and switch tabs, and the reading of what they answer.
/// Their own names start with `floe`, so none collides with a term of a browser's dictionary.
nonisolated enum BrowserTabScripts {
    static let fieldSeparator = "\u{1F}"
    static let rowSeparator = "\u{1E}"
    /// What the switching script answers when it found the tab.
    static let switched = "ok"

    /// A value as text; a tab without a title or an address reports `missing value`.
    private static let textHandler = """
    on floeText(floeValue)
        if floeValue is missing value then return ""
        return floeValue as text
    end floeText
    """

    /// One row per tab: window, key, title, address. Asks nothing of a browser that is not running.
    static func list(_ browser: BrowserApp) -> String {
        let app = "application id \(AppleScript.literal(browser.bundleID))"
        let keys = browser.tabKey == .id ? "set floeKeys to id of tabs of floeWindow" : "set floeKeys to {}"
        let key = browser.tabKey == .id ? "my floeText(item floeIndex of floeKeys)" : "(floeIndex as text)"
        return """
        set floeField to character id 31
        set floeRow to character id 30
        set floeOutput to ""
        if \(app) is running then
            tell \(app)
                repeat with floeWindow in windows
                    try
                        set floeWindowKey to (id of floeWindow) as text
                        set floeTitles to \(browser.titleTerm) of tabs of floeWindow
                        set floeAddresses to URL of tabs of floeWindow
                        \(keys)
                        repeat with floeIndex from 1 to count of floeTitles
                            set floeOutput to floeOutput & floeWindowKey & floeField & \(key) & floeField & my floeText(item floeIndex of floeTitles) & floeField & my floeText(item floeIndex of floeAddresses) & floeRow
                        end repeat
                    end try
                end repeat
            end tell
        end if
        return floeOutput

        \(textHandler)
        """
    }

    static func parse(_ output: String, browser: BrowserApp) -> [BrowserTab] {
        output.components(separatedBy: rowSeparator).compactMap { row in
            let fields = row.components(separatedBy: fieldSeparator)
            guard fields.count == 4, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            return BrowserTab(browser: browser, window: fields[0], key: fields[1], title: fields[2], url: fields[3])
        }
    }

    /// Brings a tab and its window forward, and answers `switched`. A tab that was closed since it
    /// was listed, or a browser that has quit, answers nothing and changes nothing.
    static func activate(_ tab: BrowserTab) -> String {
        let app = "application id \(AppleScript.literal(tab.browser.bundleID))"
        // By position, the tab is the one at its place if the address is still there, else the first with that address.
        let (term, wanted, hint) = tab.browser.tabKey == .id ? ("id", tab.key, 0) : ("URL", tab.url, Int(tab.key) ?? 0)
        let select = tab.browser.select.joined(separator: "\n                ")
        return """
        if \(app) is running then
            tell \(app)
                repeat with floeWindow in windows
                    if ((id of floeWindow) as text) is \(AppleScript.literal(tab.window)) then
                        set floeWanted to \(AppleScript.literal(wanted))
                        set floeValues to \(term) of tabs of floeWindow
                        set floeIndex to 0
                        if \(hint) > 0 and (count of floeValues) >= \(hint) and my floeText(item \(max(hint, 1)) of floeValues) is floeWanted then
                            set floeIndex to \(hint)
                        else
                            repeat with floeEach from 1 to count of floeValues
                                if my floeText(item floeEach of floeValues) is floeWanted then
                                    set floeIndex to floeEach
                                    exit repeat
                                end if
                            end repeat
                        end if
                        if floeIndex is 0 then return ""
                        \(select)
                        activate
                        return \(AppleScript.literal(switched))
                    end if
                end repeat
            end tell
        end if
        return ""

        \(textHandler)
        """
    }
}

/// Listing, matching and switching, each with the script runner passed in.
nonisolated enum BrowserTabs {
    /// What the browsers answered: their tabs, and the browsers macOS would not let Floe ask.
    struct Snapshot: Equatable, Sendable {
        var tabs: [BrowserTab] = []
        var refused: [BrowserApp] = []
    }

    /// Asks each browser in turn.
    static func read(_ browsers: [BrowserApp], run: AppleScriptRunner) async -> Snapshot {
        var snapshot = Snapshot()
        for browser in browsers {
            switch await run(BrowserTabScripts.list(browser)) {
            case let .text(output): snapshot.tabs += BrowserTabScripts.parse(output, browser: browser)
            case .refused: snapshot.refused.append(browser)
            case .failed: break
            }
        }
        return snapshot
    }

    /// Tabs whose title and address together hold every word of the query. A tab with all of them
    /// in its title comes before one found by its address; otherwise the browsers' order is kept.
    static func matching(_ tabs: [BrowserTab], query: String) -> [BrowserTab] {
        let words = folded(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var byTitle: [BrowserTab] = []
        var byAddress: [BrowserTab] = []
        for tab in tabs {
            let title = folded(tab.title)
            if words.allSatisfy(title.contains) {
                byTitle.append(tab)
            } else if words.allSatisfy((title + " " + folded(tab.url)).contains) {
                byAddress.append(tab)
            }
        }
        return byTitle + byAddress
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Brings a tab forward and reports back on the main thread.
    static func activate(_ tab: BrowserTab, run: @escaping AppleScriptRunner = AppleScript.run, completion: @escaping @MainActor (AppleScriptOutcome) -> Void) {
        let source = BrowserTabScripts.activate(tab)
        let lease = PanelWork.begin()
        Task(priority: .userInitiated) {
            defer { withExtendedLifetime(lease) {} }
            await completion(run(source))
        }
    }
}
