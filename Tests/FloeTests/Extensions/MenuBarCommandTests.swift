//
//  MenuBarCommandTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct MenuBarCommandTests {
    private let status = ExtensionCommand(
        extensionDir: URL(fileURLWithPath: "/tmp/floe-menu-bar-tests"), extensionName: "floe-menu-bar-tests",
        extensionTitle: "Tests", source: .local, name: "status", title: "Unread Notifications",
        mode: "menu-bar", interval: 900, icon: nil, arguments: [], extensionPreferences: [], commandPreferences: []
    )

    private func makeModel() -> (LauncherModel, AppSettings) {
        let settings = AppSettings(defaults: MemoryDefaults())
        let planets = Fixture.command("planets", extension: "floe-menu-bar-tests")
        return (LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [planets, status])), settings)
    }

    @Test func aMenuBarCommandStaysOutOfTheMenuBarUntilItIsAdded() {
        let (model, settings) = makeModel()
        #expect(model.enabledCommands.map(\.name) == ["planets"], "nothing starts on its own")
        #expect(settings.menuBarCommands.isEmpty)

        model.toggleMenuBarCommand(status)
        #expect(model.enabledCommands.map(\.name) == ["planets", "status"])
        #expect(settings.menuBarCommands == [status.id])

        model.toggleMenuBarCommand(status)
        #expect(model.enabledCommands.map(\.name) == ["planets"])
    }

    @Test func runningItFromTheSearchIsWhatAddsAndRemovesIt() throws {
        let (model, _) = makeModel()
        var shown: [String] = []
        model.panelHost.showHUD = { shown.append($0) }
        model.query = "unread"
        let item = try #require(model.results.first?.item)
        #expect(item.id == "command:\(status.id)")
        #expect(item.kind == "Menu Bar")
        #expect(model.primaryActionTitle(for: item) == "Add to Menu Bar")

        model.activate(item)
        #expect(model.isInMenuBar(status))
        #expect(model.runner.session == nil, "it gets a status item, not a view in the panel")
        #expect(model.primaryActionTitle(for: item) == "Remove from Menu Bar")

        model.activate(item)
        #expect(!model.isInMenuBar(status))
        #expect(shown == ["Added to Menu Bar", "Removed from Menu Bar"])
    }

    @Test func anOrdinaryCommandStillOpens() {
        let (model, _) = makeModel()
        #expect(model.primaryActionTitle(for: .command(Fixture.command("planets"))) == "Open")
        #expect(RootItem.command(Fixture.command("planets")).kind == "Command")
    }
}
