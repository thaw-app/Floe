//
//  MenuBarOfferTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct MenuBarOfferTests {
    private func commands(_ json: String, folder: URL = URL(fileURLWithPath: "/floe-tests-no-such-folder")) -> [ExtensionCommand] {
        ExtensionCommand.commands(inManifest: Data(json.utf8), folder: folder, source: .local)
    }

    private let player = """
    {"name": "floe-test-player", "title": "Player", "commands": [
        {"name": "now", "title": "Now Playing", "mode": "menu-bar"},
        {"name": "mini", "title": "Mini Player", "mode": "menu-bar"},
        {"name": "search", "title": "Search Tracks", "mode": "view"}
    ]}
    """

    @Test func anExtensionWithoutAMenuBarCommandAsksNothing() {
        let plain = commands(#"{"name": "floe-test-plain", "commands": [{"name": "run", "mode": "view"}, {"name": "sync", "mode": "no-view"}]}"#)
        #expect(MenuBarOffer(commands: plain, inMenuBar: []) { _ in false } == nil)
        #expect(MenuBarOffer(commands: [], inMenuBar: []) { _ in false } == nil)
    }

    @Test func theMenuBarCommandsAreOfferedByNameAndTheOthersAreLeftOut() throws {
        let offer = try #require(MenuBarOffer(commands: commands(player), inMenuBar: []) { _ in false })
        #expect(offer.ready.map(\.id) == ["floe-test-player/now", "floe-test-player/mini"])
        #expect(offer.needingSetup.isEmpty)
        #expect(offer.title == "Add Player to the menu bar?")
        #expect(offer.message == "Now Playing and Mini Player can show in the menu bar. Floe adds a menu bar command only when you ask, and you can change this later under General.")
    }

    @Test func aCommandAlreadyInTheMenuBarIsNotOfferedAgain() throws {
        let offer = try #require(MenuBarOffer(commands: commands(player), inMenuBar: ["floe-test-player/now"]) { _ in false })
        #expect(offer.ready.map(\.title) == ["Mini Player"])
        #expect(MenuBarOffer(commands: commands(player), inMenuBar: ["floe-test-player/now", "floe-test-player/mini"]) { _ in false } == nil)
    }

    @Test func aCommandThatNeedsItsPreferencesIsNamedAndNotAdded() throws {
        let offer = try #require(MenuBarOffer(commands: commands(player), inMenuBar: []) { $0.name == "mini" })
        #expect(offer.ready.map(\.title) == ["Now Playing"])
        #expect(offer.needingSetup.map(\.title) == ["Mini Player"])
        #expect(offer.message.hasSuffix("Set Player's preferences on its page before adding Mini Player."))
        #expect(offer.message.hasPrefix("Now Playing can show in the menu bar."))

        let blocked = try #require(MenuBarOffer(commands: commands(player), inMenuBar: []) { _ in true })
        #expect(blocked.ready.isEmpty)
        #expect(blocked.message == "Set Player's preferences on its page before adding Now Playing and Mini Player.")
    }

    @Test func theOfferForAnInstalledExtensionIsReadFromItsManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-offer-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("floe-test-player", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(player.utf8).write(to: folder.appendingPathComponent("package.json"))
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)

        let offer = try #require(ExtensionStore.menuBarOffer(for: "floe-test-player", in: root, settings: settings))
        #expect(offer.ready.map(\.title) == ["Now Playing", "Mini Player"])

        settings.menuBarCommands = ["floe-test-player/now", "floe-test-player/mini"]
        #expect(ExtensionStore.menuBarOffer(for: "floe-test-player", in: root, settings: settings) == nil, "nothing left to add")
        #expect(ExtensionStore.menuBarOffer(for: "floe-test-missing", in: root, settings: settings) == nil, "no manifest, no question")
    }

    @Test func aMenuBarCommandThatIsOffByDefaultIsNotOffered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-offer-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("floe-test-player", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = player.replacingOccurrences(of: #""name": "mini","#, with: #""name": "mini", "disabledByDefault": true,"#)
        try Data(manifest.utf8).write(to: folder.appendingPathComponent("package.json"))
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)

        let offer = try #require(ExtensionStore.menuBarOffer(for: "floe-test-player", in: root, settings: settings))
        #expect(offer.ready.map(\.title) == ["Now Playing"])
    }
}
