//
//  AlternativeActionRulesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing
import ThawUI

@MainActor
struct AlternativeActionRulesTests {
    private func row(_ id: ActionID, _ title: String, children: [ItemAction] = []) -> ItemAction {
        ItemAction(title: title, symbol: "circle", children: children, id: id)
    }

    private func titles(_ rows: [ItemAction?]) -> [String] {
        rows.map { $0?.title ?? "-" }
    }

    private let commandO = KeyCombination(key: .o, modifiers: .command)
    private let commandY = FloeKeys.commandY
    private let commandReturn = FloeKeys.commandReturn
    private let files = ActionKeys.floe(for: .file)

    private var menu: [ItemAction?] {
        [
            row(.openWith, "Open With", children: [row(.openWith(URL(fileURLWithPath: "/Fake/Zed.app")), "Zed")]),
            row(.showInFinder, "Show in Finder"),
            nil,
            row(.copyPath, "Copy Path"),
            row(.copyName, "Copy Name"),
        ]
    }

    // MARK: Return

    @Test func returnRunsTheFirstDefaultOnOffer() {
        var choices = KindActions()
        choices.defaults = [ActionID(rawValue: "floe:gone"), .copyName, .copyPath]
        let offered = AlternativeActionRules.offered(menu)
        #expect(AlternativeActionRules.primary(choices, offered: offered)?.title == "Copy Name", "a default that is gone is passed over")
        choices.defaults = [.openWith, .copyPath]
        #expect(AlternativeActionRules.primary(choices, offered: offered)?.title == "Copy Path", "a submenu runs nothing itself")
        choices.defaults = [ActionID(rawValue: "floe:gone")]
        #expect(AlternativeActionRules.primary(choices, offered: offered) == nil, "with none on offer, Return is Floe's own")
        #expect(AlternativeActionRules.primary(KindActions(), offered: offered) == nil)
    }

    @Test func aRowInASubmenuIsOnOffer() {
        let offered = AlternativeActionRules.offered(menu)
        #expect(offered[.openWith(URL(fileURLWithPath: "/Fake/Zed.app"))]?.title == "Zed")
    }

    // MARK: The Actions menu

    @Test func aMenuNobodyChangedStaysAsFloeHasIt() {
        #expect(titles(AlternativeActionRules.arranged(menu, own: nil, primaryID: nil, choices: KindActions())) == titles(menu))
    }

    @Test func choicesWithNoDefaultLeaveTheMenuStartingAsFloeHasIt() {
        var choices = KindActions()
        choices.shortcuts = [.copyName: commandO]
        #expect(titles(AlternativeActionRules.arranged(menu, own: nil, primaryID: nil, choices: choices)) == titles(menu), "no separator under the Return row")
        choices.hidden = [.copyName]
        #expect(titles(AlternativeActionRules.arranged(menu, own: nil, primaryID: nil, choices: choices)) == ["Open With", "Show in Finder", "-", "Copy Path"])
    }

    @Test func aDefaultMovesFloesOwnReturnToTheTopAndLeavesItsOwnRowOut() {
        let own = row(.own, "Open")
        var choices = KindActions()
        choices.defaults = [.copyPath]
        let rows = AlternativeActionRules.arranged(menu, own: own, primaryID: .copyPath, choices: choices)
        #expect(titles(rows) == ["-", "Open", "Open With", "Show in Finder", "-", "Copy Name"])
    }

    @Test func hiddenRowsAreLeftOutAndAnEmptySubmenuWithThem() {
        var choices = KindActions()
        choices.hidden = [.showInFinder, .openWith(URL(fileURLWithPath: "/Fake/Zed.app")), .own]
        let rows = AlternativeActionRules.arranged(menu, own: row(.own, "Open"), primaryID: nil, choices: choices)
        #expect(titles(rows) == ["-", "Open", "-", "Copy Path", "Copy Name"], "Floe's own Return is never hidden")
    }

    @Test func theMenuKeepsTheKeysItsRowsCameWith() {
        var choices = KindActions()
        choices.hidden = [.showInFinder]
        let rows = AlternativeActionRules.arranged(files.keyed(menu), own: nil, primaryID: nil, choices: choices).compactMap(\.self)
        #expect(rows.first { $0.id == .copyPath }?.shortcut == FloeKeys.commandShiftC)
        #expect(!rows.contains { $0.id == .showInFinder })
    }

    @Test func separatorsAreTidied() {
        let rows = AlternativeActionRules.tidied([nil, nil, row(.copyPath, "Copy Path"), nil, nil, row(.copyName, "Copy Name"), nil])
        #expect(titles(rows) == ["-", "Copy Path", "-", "Copy Name"])
    }

    // MARK: Keys

    @Test func keysNeedCommandAndMayNotBeTheLaunchers() {
        #expect(AlternativeActionRules.canBeChosen(commandO))
        #expect(AlternativeActionRules.canBeChosen(KeyCombination(key: .o, modifiers: [.command, .option])))
        #expect(!AlternativeActionRules.canBeChosen(KeyCombination(key: .l, modifiers: .option)), "Option types characters on many layouts")
        #expect(!AlternativeActionRules.canBeChosen(KeyCombination(key: .o, modifiers: .control)))
        #expect(!AlternativeActionRules.canBeChosen(KeyCombination(key: .o, modifiers: [])))
        let commandC = KeyCombination(key: KeyLayout.current.key(typing: "c"), modifiers: .command)
        for taken in [KeyCombination(key: .k, modifiers: .command), commandC, KeyCombination(key: .leftArrow, modifiers: .command)] {
            #expect(!AlternativeActionRules.canBeChosen(taken), "\(taken.displayValue) is the launcher's or the list's")
        }
        for rowKeys in [commandY, FloeKeys.commandShiftF, FloeKeys.commandShiftC, commandReturn] {
            #expect(AlternativeActionRules.canBeChosen(rowKeys), "\(rowKeys.displayValue) is a row's, which a row of a kind without it can have")
        }
        for withReturn in [[.command, .option], [.command, .shift], [.command, .control]] as [Modifiers] {
            #expect(AlternativeActionRules.canBeChosen(KeyCombination(key: .returnKey, modifiers: withReturn)), "Return with Command is asked of the row before Return")
        }
        #expect(!AlternativeActionRules.canBeChosen(KeyCombination(key: .returnKey, modifiers: [.option])), "but never without Command")
    }

    @Test func keysTheListAndTheSearchFieldUseCanNeverBeChosen() {
        // With Command and anything else held these still move or leave: Up on the top row recalls an earlier search.
        // Enter on the keypad is read as Return, so keys with Return stand for it.
        let held: [Modifiers] = [.command, [.command, .option], [.command, .control], [.command, .shift, .option], [.command, .option, .control]]
        let keys: [KeyCode] = [.upArrow, .downArrow, .leftArrow, .rightArrow, .pageUp, .pageDown, .delete, .forwardDelete, .home, .end, .keypadEnter, .escape]
        for key in keys {
            for modifiers in held {
                let combination = KeyCombination(key: key, modifiers: modifiers)
                #expect(!AlternativeActionRules.canBeChosen(combination), "\(combination.displayValue) is the list's or the search field's")
            }
        }
    }

    @Test func everyKeyOfTheMainMenuIsReserved() {
        // The Window menu's keys count too, though only the Settings process has it.
        let app = NSApplication.shared
        let previous = app.windowsMenu
        defer { app.windowsMenu = previous }
        let main = MainMenu.make(target: NSObject(), about: #selector(NSObject.description), settings: #selector(NSObject.description))
        let reserved = AlternativeActionRules.reservedKeys()
        for item in main.items.flatMap({ $0.submenu?.items ?? [] }) where !item.keyEquivalent.isEmpty {
            let isShifted = item.keyEquivalent != item.keyEquivalent.lowercased()
            let modifiers = Modifiers(nsEventFlags: item.keyEquivalentModifierMask).union(isShifted ? .shift : [])
            let taken = reserved.contains { $0.modifiers == modifiers && $0.key.keyEquivalent == item.keyEquivalent.lowercased() }
            #expect(taken, "\(item.title) is not in reservedKeys")
        }
    }

    @Test func theMainMenusKeysAreTheKeysThatTypeItsLettersAndTheLaunchersTheKeysPressed() {
        let us = Dictionary(uniqueKeysWithValues: KeyLayout.us.map { ($0.value, String($0.key)) })
        let qwertz = KeyLayout { key in key == .y ? "z" : key == .z ? "y" : us[key] ?? "" }
        let reserved = AlternativeActionRules.reservedKeys(on: qwertz)
        #expect(reserved.contains(KeyCombination(key: .y, modifiers: .command)), "Undo is the key that types z there")
        #expect(!reserved.contains(KeyCombination(key: .z, modifiers: .command)), "and the key that types y is free, as Floe's ⌘Y")
        #expect(reserved.contains(KeyCombination(key: .k, modifiers: .command)), "⌘K is the key pressed, as the launcher reads it")
    }

    // MARK: The user's keys over Floe's

    @Test func theUsersKeysReplaceFloesOnTheirRow() {
        var choices = KindActions()
        choices.shortcuts = [.quickLook: commandO]
        let keys = files.applying(choices)
        #expect(keys.key(for: .quickLook) == commandO)
        #expect(!keys.keys.values.contains(commandY), "Floe's ⌘Y is no row's now")
        #expect(keys.key(for: .showInFinder) == commandReturn, "Floe's ⌘↩ stays")
    }

    @Test func keysTakenOffARowAreGone() {
        var choices = KindActions()
        choices.clearedKeys = [.quickLook]
        let keys = files.applying(choices)
        #expect(keys.key(for: .quickLook) == nil)
        #expect(keys.key(for: .copyPath) == FloeKeys.commandShiftC)
    }

    @Test func theUsersKeysTakeAnotherRowsAwayFromIt() {
        // Settings refuses this, but sync, or keys Floe gives a row later, can bring it about.
        var choices = KindActions()
        choices.shortcuts = [.copyName: commandY]
        let keys = files.applying(choices)
        #expect(keys.key(for: .copyName) == commandY)
        #expect(keys.key(for: .quickLook) == nil)
    }

    @Test func keysTheUserCannotChooseArePassedOverHoweverTheyWereStored() {
        var choices = KindActions()
        choices.shortcuts = [.copyName: KeyCombination(key: .k, modifiers: .command), .copyFile: KeyCombination(key: .leftArrow, modifiers: .command)]
        let keys = files.applying(choices)
        #expect(keys.key(for: .copyName) == nil)
        #expect(keys.key(for: .copyFile) == nil)
        #expect(keys.key(for: .showInFinder) == commandReturn, "and Floe's keys stay where they were")
    }

    @Test func twoOfTheUsersRowsWithTheSameKeysGoToTheFirstByName() {
        var choices = KindActions()
        choices.shortcuts = [.copyPath: commandO, .copyName: commandO, ActionID(rawValue: "floe:gone"): KeyCombination(key: .g, modifiers: .command)]
        let keys = ActionKeys.floe(for: .url).applying(choices)
        #expect(keys.key(for: .copyName) == commandO, "floe:copyName comes before floe:copyPath")
        #expect(keys.key(for: .copyPath) == nil)
        #expect(keys.row(for: KeyCombination(key: .g, modifiers: .command), in: menu) == nil, "keys for a row no menu offers run nothing")
    }

    // MARK: Settings

    @Test func choicesAreWrittenTheSameWayEachTime() throws {
        var choices = KindActions()
        choices.defaults = [.copyPath]
        choices.hidden = [.showInFinder, .copyName, .quickLook, .moveToTrash, .copyFile]
        choices.shortcuts = [.copyName: commandO]
        choices.clearedKeys = [.quickLook, .copyPath]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = try #require(String(bytes: encoder.encode(choices), encoding: .utf8))
        #expect(text.contains(#""hidden":["floe:copyFile","floe:copyName","floe:moveToTrash","floe:quickLook","floe:showInFinder"]"#))
        #expect(text.contains(#""shortcuts":{"floe:copyName":[31,8]}"#))
        #expect(text.contains(#""clearedKeys":["floe:copyPath","floe:quickLook"]"#))
        #expect(try JSONDecoder().decode(KindActions.self, from: Data(text.utf8)) == choices)
    }

    @Test func choicesWithKeysMissingStillRead() throws {
        let read = try JSONDecoder().decode(KindActions.self, from: Data(#"{"defaults":["floe:copyPath"]}"#.utf8))
        #expect(read.defaults == [.copyPath])
        #expect(read.hidden.isEmpty && read.shortcuts.isEmpty && read.clearedKeys.isEmpty)
    }
}
