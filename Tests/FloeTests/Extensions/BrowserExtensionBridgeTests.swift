//
//  BrowserExtensionBridgeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// BrowserExtension from the browser itself, with scripts that are read and never run.
struct BrowserExtensionBridgeTests {
    @Test func theFrontmostBrowserIsAskedElseTheFirstOneRunning() throws {
        #expect(try BrowserExtensionBridge.browser(frontmost: "com.google.Chrome", running: { _ in false }) == .chrome)
        #expect(try BrowserExtensionBridge.browser(frontmost: "com.apple.Notes", running: { $0 == .dia }) == .dia)
        #expect(throws: RequestRefusal.self) {
            try BrowserExtensionBridge.browser(frontmost: nil, running: { _ in false })
        }
    }

    @Test func tabsAreReadWithTheirIdsAndTheActiveOne() {
        let field = BrowserTabScripts.fieldSeparator
        let row = BrowserTabScripts.rowSeparator
        let output = "12\(field)Floe\(field)https://floe.test\(field)1\(row)13\(field)\(field)about:blank\(field)0\(row)abc\(field)Odd\(field)https://odd.test\(field)0\(row)"
        let tabs = BrowserExtensionBridge.parseTabs(output)

        #expect(tabs.count == 3)
        #expect(tabs[0]["id"] as? Int == 12 && tabs[0]["title"] as? String == "Floe" && tabs[0]["active"] as? Bool == true)
        #expect(tabs[1]["active"] as? Bool == false && tabs[1]["url"] as? String == "about:blank")
        #expect(tabs[2]["id"] == nil, "an id that is not a number is left out, the tab is not")
    }

    @Test func eachBrowserIsAskedInTheTermsOfItsOwnDictionary() {
        let safari = BrowserExtensionBridge.tabsScript(.safari)
        #expect(safari.contains("index of current tab of front window"))
        #expect(safari.contains("(id of floeWindow) * 1000 + floeIndex"))
        let chrome = BrowserExtensionBridge.tabsScript(.chrome)
        #expect(chrome.contains("id of active tab of front window") && chrome.contains("title of floeTab"))
        #expect(!safari.contains("activate") && !chrome.contains("activate"), "reading the tabs brings nothing forward")
    }

    @Test func theScriptRunsInTheTabAskedForOrTheActiveOne() {
        #expect(BrowserExtensionBridge.runScript("1", tabID: nil, in: .safari).contains("do JavaScript \"1\" in current tab of front window"))
        #expect(BrowserExtensionBridge.runScript("1", tabID: 5003, in: .safari).contains("in tab 3 of window id 5"))
        #expect(BrowserExtensionBridge.runScript("1", tabID: nil, in: .chrome).contains("set floeTab to active tab of front window"))
        let byID = BrowserExtensionBridge.runScript("document.title", tabID: 42, in: .helium)
        #expect(byID.contains("is \"42\" then set floeTab") && byID.contains("execute floeTab javascript \"document.title\""))
    }

    @Test func aRefusalOrADisabledOptionIsSaidInWords() throws {
        #expect(throws: RequestRefusal.self) {
            try BrowserExtensionBridge.answer(AppleScript.Execution(didRun: false, hasError: true, errorNumber: AppleScript.refusedErrorNumber), from: .safari)
        }
        do {
            _ = try BrowserExtensionBridge.answer(AppleScript.Execution(didRun: false, hasError: true, errorMessage: "Allow JavaScript from Apple Events"), from: .chrome)
            Issue.record("a failed script answered")
        } catch {
            #expect(error.localizedDescription == "Allow JavaScript from Apple Events", "the browser's own message says which option to turn on")
        }
        #expect(try BrowserExtensionBridge.answer(AppleScript.Execution(text: "{}"), from: .chrome) == "{}")
    }
}
