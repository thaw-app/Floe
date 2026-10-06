//
//  CommandLookupTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct CommandLookupTests {
    private static func commands(extension name: String, title: String, _ commands: [(name: String, title: String)]) -> [ExtensionCommand] {
        let manifest: [String: Any] = [
            "name": name,
            "title": title,
            "commands": commands.map { ["name": $0.name, "title": $0.title, "mode": "view"] },
        ]
        return ExtensionCommand.commands(inManifest: Fixture.manifest(manifest), folder: URL(fileURLWithPath: "/extensions/\(name)"), source: .local)
    }

    private let all = commands(extension: "hello", title: "Hello", [("planets", "Show Planets"), ("greet", "Greet")])
        + commands(extension: "kill-process", title: "Kill Process", [("index", "Kill Process")])
        + commands(extension: "calendar", title: "Planner", [("today", "Today"), ("show", "Show Week")])

    @Test func commandsOfDisabledExtensionsAreLeftOut() {
        let enabled = CommandLookup.enabled(all, disabledExtensions: ["hello"])
        #expect(enabled.map(\.id) == ["kill-process/index", "calendar/today", "calendar/show"])
    }

    @Test func aCommandSwitchedOffIsLeftOutAndItsExtensionsOthersStay() {
        let enabled = CommandLookup.enabled(all, disabledExtensions: [], disabledCommands: ["hello/greet", "calendar/today"])
        #expect(enabled.map(\.id) == ["hello/planets", "kill-process/index", "calendar/show"])
        #expect(CommandLookup.command(withID: "hello/greet", in: enabled) == nil)
    }

    @Test func anExtensionSwitchedOffTakesItsCommandsWhateverTheirOwnSwitchSays() {
        let enabled = CommandLookup.enabled(all, disabledExtensions: ["calendar"], disabledCommands: ["hello/greet"])
        #expect(enabled.map(\.id) == ["hello/planets", "kill-process/index"])
    }

    @Test func nothingDisabledKeepsEveryCommandInScanOrder() {
        #expect(CommandLookup.enabled(all, disabledExtensions: []).map(\.id) == all.map(\.id))
    }

    @Test func aCommandIsFoundByItsIdentifier() throws {
        let command = try #require(CommandLookup.command(withID: "hello/greet", in: all))
        #expect(command.title == "Greet")
    }

    @Test func anIdentifierFromAStaleShortcutFindsNothing() {
        #expect(CommandLookup.command(withID: "hello/removed", in: all) == nil)
        #expect(CommandLookup.command(withID: "greet", in: all) == nil)
        #expect(CommandLookup.command(withID: "", in: all) == nil)
    }

    @Test func aDisabledCommandIsNotFoundAmongTheEnabledOnes() {
        let enabled = CommandLookup.enabled(all, disabledExtensions: ["hello"])
        #expect(CommandLookup.command(withID: "hello/greet", in: enabled) == nil)
    }

    @Test func identifiersResolveInTheOrderAskedForAndSkipUnknownOnes() {
        let found = CommandLookup.commands(withIDs: ["calendar/today", "gone/gone", "hello/planets"], in: all)
        #expect(found.map(\.id) == ["calendar/today", "hello/planets"])
    }

    @Test func anEmptyQueryMatchesEveryCommand() {
        #expect(CommandLookup.matching("", in: all).map(\.id) == all.map(\.id))
        #expect(CommandLookup.matching("  \n", in: all).map(\.id) == all.map(\.id))
    }

    @Test func aCommandMatchesOnItsExtensionsTitleToo() {
        #expect(CommandLookup.matching("planner", in: all).map(\.id) == ["calendar/today", "calendar/show"])
    }

    @Test func aTitleMatchRanksAboveTheSameMatchOnAnExtension() throws {
        let titled = Self.commands(extension: "notes", title: "Notes", [("planner", "Planner")])
        let ranked = CommandLookup.matching("planner", in: all + titled)
        #expect(ranked.map(\.id) == ["notes/planner", "calendar/today", "calendar/show"])
        let command = try #require(titled.first)
        #expect(CommandLookup.score(query: "planner", command: command) == 100)
    }

    @Test func betterMatchesComeFirst() {
        // "Show Week" is the shorter title, so the prefix covers more of it.
        #expect(CommandLookup.matching("show", in: all).map(\.id) == ["calendar/show", "hello/planets"])
    }

    @Test func equalMatchesKeepScanOrder() {
        #expect(CommandLookup.matching("hello", in: all).map(\.id) == ["hello/planets", "hello/greet"])
    }

    @Test func theQueryIsTrimmedAndCaseInsensitive() {
        #expect(CommandLookup.matching("  GREET ", in: all).first?.id == "hello/greet")
    }

    @Test func aQueryThatMatchesNothingReturnsNothing() {
        #expect(CommandLookup.matching("zzzq", in: all).isEmpty)
    }

    @Test func theScoreIsNilWhenNeitherTitleMatches() throws {
        let command = try #require(all.first)
        #expect(CommandLookup.score(query: "zzzq", command: command) == nil)
        #expect(CommandLookup.score(query: "hello", command: command) == 90)
    }
}
