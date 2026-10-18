//
//  CommandSubtitlesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct CommandSubtitlesTests {
    @Test func aSubtitleStaysUntilTheCommandClearsIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-subtitles-tests-\(UUID().uuidString)"))
        CommandSubtitles.set("3 unread", for: "mail/inbox", in: defaults)
        CommandSubtitles.set("12°", for: "weather/now", in: defaults)
        #expect(CommandSubtitles.subtitle(for: "mail/inbox", in: defaults) == "3 unread")

        CommandSubtitles.set(nil, for: "mail/inbox", in: defaults)
        CommandSubtitles.set("", for: "weather/now", in: defaults)
        #expect(CommandSubtitles.subtitle(for: "mail/inbox", in: defaults) == nil)
        #expect(CommandSubtitles.subtitle(for: "weather/now", in: defaults) == nil, "an empty one clears it too")
    }

    @Test func theRowShowsTheSetSubtitleThenTheManifestsThenTheKind() throws {
        let manifest = Fixture.manifest([
            "name": "mail-\(UUID().uuidString)", "title": "Mail",
            "commands": [["name": "inbox", "title": "Inbox", "subtitle": "Gmail"], ["name": "compose", "title": "Compose"]],
        ])
        let commands = ExtensionCommand.commands(inManifest: manifest, folder: URL(fileURLWithPath: "/tmp/mail"), source: .local)
        let inbox = try #require(commands.first { $0.name == "inbox" })
        let compose = try #require(commands.first { $0.name == "compose" })
        #expect(RootItem.command(inbox).rowLabel == "Gmail")
        #expect(RootItem.command(compose).rowLabel == RootItem.command(compose).kind)

        CommandSubtitles.set("3 unread", for: inbox.id)
        defer { CommandSubtitles.set(nil, for: inbox.id) }
        #expect(RootItem.command(inbox).rowLabel == "3 unread")
    }
}
