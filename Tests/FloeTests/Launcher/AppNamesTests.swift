//
//  AppNamesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct AppNamesTests {
    @Test(arguments: [
        ("备忘录", ["bei wang lu", "beiwanglu"]),
        ("微信", ["wei xin", "weixin"]),
        ("メモ", ["memo"]),
        ("Калькулятор", ["Kalkulator"]),
        ("Café", ["Cafe"]),
        ("Notes", []),
    ])
    func aNameIsSpelledAsALatinKeyboardTypesIt(name: String, spellings: [String]) {
        #expect(AppNames.latinSpellings(of: name) == spellings)
    }

    @Test func otherNamesLeaveOutTheShownOneRepeatsAndTheFileName() {
        let read = ["Preferences", "Settings", "System Settings.app", "System Preferences", "System Settings", "settings", ""]
        #expect(AppNames.others(of: "System Settings", among: read) == ["Preferences", "Settings", "System Preferences"])
    }

    @Test func eachAppGetsItsOwnNamesAndTheirSpellings() {
        let apps = ["Notes", "WeChat", "Safari"].map { AppEntry(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app")) }
        let filled = AppNames.filling(apps) { url in
            switch url.deletingPathExtension().lastPathComponent {
            case "Notes": ["备忘录", "Notes.app"]
            case "WeChat": ["微信"]
            default: []
            }
        }
        #expect(filled.map(\.name) == ["Notes", "WeChat", "Safari"], "in the order they came")
        #expect(filled[0].otherNames == ["备忘录"])
        #expect(filled[0].spellings == ["bei wang lu", "beiwanglu"])
        #expect(filled[1].spellings == ["wei xin", "weixin"])
        #expect(filled[2].otherNames.isEmpty && filled[2].spellings.isEmpty)
    }

    @Test func spotlightKnowsSystemSettingsByItsOldName() {
        #expect(AppNames.spotlight(URL(fileURLWithPath: "/nowhere/Gone.app")).isEmpty)
        let names = AppNames.spotlight(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        // A Mac whose Spotlight hasn't indexed the system volume reads no names at all.
        if !names.isEmpty {
            #expect(names.contains("System Preferences"))
        }
    }

    @Test func twoAppsOfOneNameKeepTheirOtherNames() {
        let first = AppEntry(name: "Notes", url: URL(fileURLWithPath: "/Applications/Notes.app"), otherNames: ["备忘录"])
        let second = AppEntry(name: "Notes", url: URL(fileURLWithPath: "/Other/Notes.app"))
        let kept = AppEntry.distinct([first, second], identifier: { $0.path }, folderName: { $0.deletingLastPathComponent().lastPathComponent })
        #expect(kept.map(\.origin) == ["Applications", "Other"])
        #expect(kept.first?.otherNames == ["备忘录"])
    }
}
