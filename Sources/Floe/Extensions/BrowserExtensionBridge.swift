//
//  BrowserExtensionBridge.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Answers Raycast's BrowserExtension API from the browser itself, through AppleScript, where Raycast asks its
/// companion browser extension. The browser is the frontmost one Floe can script, else the first one running.
nonisolated enum BrowserExtensionBridge {
    /// Safari's tabs have no id, so one is made of the window's id and the tab's place in it.
    static let safariTabsPerWindow = 1000

    /// The messages go to the extension's own code, which shows or logs them, so they stay in English.
    static func browser(frontmost: String?, running: (BrowserApp) -> Bool = BrowserApp.isRunning) throws -> BrowserApp {
        if let front = BrowserApp.all.first(where: { $0.bundleID == frontmost }) {
            return front
        }
        guard let open = BrowserApp.all.first(where: running) else {
            let names = BrowserApp.all.map(\.name).joined(separator: ", ")
            throw RequestRefusal(errorDescription: "No browser Floe can read is open. Floe reads tabs from \(names).")
        }
        return open
    }

    /// One row per tab: id, title, address, and 1 for the front window's active tab.
    static func tabsScript(_ browser: BrowserApp) -> String {
        let app = "application id \(AppleScript.literal(browser.bundleID))"
        let isSafari = browser == .safari
        let tabID = isSafari
            ? "(((id of floeWindow) * \(safariTabsPerWindow) + floeIndex) as text)"
            : "((id of item floeIndex of floeTabs) as text)"
        let active = isSafari ? "index of current tab of front window" : "id of active tab of front window"
        let isActive = isSafari ? "floeIndex is floeActive" : "(id of item floeIndex of floeTabs) is floeActive"
        return """
        set floeField to character id 31
        set floeRow to character id 30
        set floeOutput to ""
        tell \(app)
            set floeActive to missing value
            set floeFront to missing value
            try
                set floeActive to \(active)
                set floeFront to id of front window
            end try
            repeat with floeWindow in windows
                set floeTabs to tabs of floeWindow
                repeat with floeIndex from 1 to count of floeTabs
                    set floeTab to item floeIndex of floeTabs
                    set floeIsActive to "0"
                    if (id of floeWindow) is floeFront and \(isActive) then set floeIsActive to "1"
                    set floeOutput to floeOutput & \(tabID) & floeField & my floeText(\(browser.titleTerm) of floeTab) & floeField & my floeText(URL of floeTab) & floeField & floeIsActive & floeRow
                end repeat
            end repeat
        end tell
        return floeOutput

        on floeText(floeValue)
            if floeValue is missing value then return ""
            return floeValue as text
        end floeText
        """
    }

    static func parseTabs(_ output: String) -> [[String: Any]] {
        output.components(separatedBy: BrowserTabScripts.rowSeparator).compactMap { row in
            let fields = row.components(separatedBy: BrowserTabScripts.fieldSeparator)
            guard fields.count == 4 else { return nil }
            var tab: [String: Any] = ["title": fields[1], "url": fields[2], "active": fields[3] == "1"]
            // Raycast's ids are numbers; a browser whose ids are not still lists its tabs.
            tab["id"] = Int(fields[0])
            return tab
        }
    }

    /// Runs the script in a tab, the front window's active one when no id is given, and answers what it returned.
    static func runScript(_ javascript: String, tabID: Int?, in browser: BrowserApp) -> String {
        let app = "application id \(AppleScript.literal(browser.bundleID))"
        let code = AppleScript.literal(javascript)
        if browser == .safari {
            let tab = tabID.map { "tab \($0 % safariTabsPerWindow) of window id \($0 / safariTabsPerWindow)" } ?? "current tab of front window"
            return """
            tell \(app)
                return do JavaScript \(code) in \(tab)
            end tell
            """
        }
        let find = tabID.map { id in
            """
            set floeTab to missing value
                repeat with floeWindow in windows
                    repeat with floeEach in tabs of floeWindow
                        if ((id of floeEach) as text) is "\(id)" then set floeTab to contents of floeEach
                    end repeat
                end repeat
                if floeTab is missing value then error "No tab has the id \(id)."
            """
        } ?? "set floeTab to active tab of front window"
        return """
        tell \(app)
            \(find)
            return execute floeTab javascript \(code)
        end tell
        """
    }

    static func tabs(frontmost: String?, run: (String) async -> AppleScript.Execution) async throws -> [[String: Any]] {
        let browser = try browser(frontmost: frontmost)
        return try parseTabs(answer(await run(tabsScript(browser)), from: browser))
    }

    static func run(_ javascript: String, tabID: Int?, frontmost: String?, run: (String) async -> AppleScript.Execution) async throws -> String {
        let browser = try browser(frontmost: frontmost)
        return try answer(await run(runScript(javascript, tabID: tabID, in: browser)), from: browser)
    }

    /// The browser's own message says how to allow scripts from Apple Events, when that is what stopped one.
    static func answer(_ execution: AppleScript.Execution, from browser: BrowserApp) throws -> String {
        if execution.isRefused {
            throw RequestRefusal(errorDescription: "Floe isn't allowed to control \(browser.name). Allow it in System Settings › Privacy & Security › Automation.")
        }
        guard let text = execution.text, !execution.hasError else {
            throw RequestRefusal(errorDescription: execution.errorMessage ?? "\(browser.name) didn't answer.")
        }
        return text
    }
}
