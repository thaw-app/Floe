//
//  CommandLinkTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// The links that were handed to the system.
private final nonisolated class Opened: Sendable {
    private let state = Mutex<[URL]>([])

    var urls: [URL] {
        state.withLock { $0 }
    }

    var opener: LinkOpener {
        LinkOpener { [self] url, _ in state.withLock { $0.append(url) } }
    }
}

@MainActor
struct CommandLinkTests {
    private let status = ExtensionCommand(
        extensionDir: URL(fileURLWithPath: "/tmp/sample"),
        extensionName: "sample",
        extensionTitle: "Sample",
        source: .local,
        name: "status",
        title: "Status",
        mode: "menu-bar",
        interval: nil,
        icon: nil,
        arguments: [],
        extensionPreferences: [],
        commandPreferences: []
    )
    private let settings: AppSettings
    private let model: LauncherModel
    private let opened = Opened()

    /// Planets needs a preference set before it runs, so running it opens its form: what a test can see of a run,
    /// without starting the extension.
    private static let planets = Fixture.command("planets", commandPreferences: [Fixture.field("token", required: true)])

    init() throws {
        settings = AppSettings(defaults: MemoryDefaults())
        model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [Self.planets, status]))
    }

    /// Opens a link as a menu-bar command does, and answers the command it ran, by its id.
    private func ran(opening target: String, in model: LauncherModel? = nil) -> String? {
        let model = model ?? self.model
        model.linkOpener = opened.opener
        model.runner.handleBackgroundMessage(["type": "open", "target": target])
        return model.setup?.command.id
    }

    @Test func aLinkToAnInstalledCommandRunsItInFloe() {
        #expect(ran(opening: "raycast://extensions/someone/sample/planets") == "sample/planets")
        #expect(model.setup?.arguments == nil, "without arguments, so the command asks for the ones it takes")
        #expect(opened.urls.isEmpty)
    }

    @Test func theArgumentsOfALinkReachTheCommand() throws {
        #expect(ran(opening: "raycast://extensions/someone/sample/planets?arguments=%7B%22name%22%3A%22Mars%20%26%20moons%22%7D&launchType=background") == "sample/planets")
        #expect(model.setup?.arguments?["name"] as? String == "Mars & moons", "kept while the form asks for the preference")
    }

    @Test(arguments: [
        "raycast://extensions/someone/sample/moons",
        "raycast://extensions/someone/other/planets",
        "raycast://extensions/raycast/raycast-ai/ai-chat",
        "raycast://extensions/sample/planets",
        "raycast://confetti",
        "raycast://focus/start?goal=Write",
    ])
    func anyOtherRaycastLinkGoesToTheSystem(target: String) throws {
        #expect(ran(opening: target) == nil)
        #expect(try opened.urls == [#require(URL(string: target))])
    }

    @Test func aLinkRunsACommandOnlyForTheOwnerItsExtensionNames() {
        var owned = Self.planets
        owned.owner = "someone"
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [owned]))
        #expect(ran(opening: "raycast://extensions/someone-else/sample/planets", in: model) == nil)
        #expect(opened.urls.count == 1, "another owner's extension of the same name is not this one")
        #expect(ran(opening: "raycast://extensions/Someone/sample/planets", in: model) == "sample/planets")
    }

    @Test func aLinkToADisabledCommandGoesToTheSystem() {
        settings.disabledCommands = ["sample/planets"]
        #expect(ran(opening: "raycast://extensions/someone/sample/planets") == nil)
        #expect(opened.urls.count == 1)
    }

    @Test func aLinkToACommandInTheMenuBarLeavesItThere() {
        settings.menuBarCommands = [status.id]
        #expect(ran(opening: "raycast://extensions/someone/sample/status") == nil)
        #expect(settings.menuBarCommands == [status.id])
        #expect(opened.urls.isEmpty, "the link is ours, so Raycast is not opened for it")
    }
}
