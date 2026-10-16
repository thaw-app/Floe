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

    init() throws {
        settings = AppSettings(defaults: MemoryDefaults())
        model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [Fixture.command("planets"), status]), isResident: true)
    }

    /// Opens a link as a menu-bar command does, and answers what the panel process was asked to run.
    private func requests(opening target: String) -> [PanelRequest] {
        var requests: [PanelRequest] = []
        model.panelHost.presentInPanelProcess = { requests.append($0) }
        model.linkOpener = opened.opener
        model.runner.handleBackgroundMessage(["type": "open", "target": target])
        return requests
    }

    private func arguments(of request: PanelRequest?) throws -> [String: String]? {
        guard case let .command(_, data) = request else { return nil }
        return try data.map { try #require(JSONSerialization.jsonObject(with: $0) as? [String: String]) }
    }

    @Test func aLinkToAnInstalledCommandRunsItInFloe() {
        let requests = requests(opening: "raycast://extensions/someone/sample/planets")
        #expect(requests == [.command("sample/planets", arguments: nil)], "without arguments, so the command asks for the ones it takes")
        #expect(opened.urls.isEmpty)
    }

    @Test func theArgumentsOfALinkReachTheCommand() throws {
        let requests = requests(opening: "raycast://extensions/someone/sample/planets?arguments=%7B%22name%22%3A%22Mars%20%26%20moons%22%7D&launchType=background")
        #expect(requests.map(\.isCommand) == [true])
        #expect(try arguments(of: requests.first) == ["name": "Mars & moons"])
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
        #expect(requests(opening: target).isEmpty)
        #expect(try opened.urls == [#require(URL(string: target))])
    }

    @Test func aLinkRunsACommandOnlyForTheOwnerItsExtensionNames() {
        var owned = Fixture.command("planets")
        owned.owner = "someone"
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [owned]), isResident: true)
        var requests: [PanelRequest] = []
        model.panelHost.presentInPanelProcess = { requests.append($0) }
        model.linkOpener = opened.opener
        model.runner.handleBackgroundMessage(["type": "open", "target": "raycast://extensions/someone-else/sample/planets"])
        #expect(requests.isEmpty)
        #expect(opened.urls.count == 1, "another owner's extension of the same name is not this one")
        model.runner.handleBackgroundMessage(["type": "open", "target": "raycast://extensions/Someone/sample/planets"])
        #expect(requests.map(\.isCommand) == [true])
    }

    @Test func aLinkToADisabledCommandGoesToTheSystem() {
        settings.disabledCommands = ["sample/planets"]
        #expect(requests(opening: "raycast://extensions/someone/sample/planets").isEmpty)
        #expect(opened.urls.count == 1)
    }

    @Test func aLinkToACommandInTheMenuBarLeavesItThere() {
        settings.menuBarCommands = [status.id]
        #expect(requests(opening: "raycast://extensions/someone/sample/status").isEmpty)
        #expect(settings.menuBarCommands == [status.id])
        #expect(opened.urls.isEmpty, "the link is ours, so Raycast is not opened for it")
    }
}

private extension PanelRequest {
    var isCommand: Bool {
        if case .command = self {
            true
        } else {
            false
        }
    }
}
