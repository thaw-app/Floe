//
//  IntentHandlerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct IntentHandlerTests {
    @Test func aHandlerAnswersFromTheModelAndPresentsWhereItIsTold() async {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        let usage = UsageStore(defaults: scratch.defaults)
        let planets = Fixture.command("planets")
        let hidden = Fixture.command("moons")
        settings.disabledCommands = [hidden.id]
        let model = LauncherModel(settings: settings, usage: usage, snapshot: CatalogSnapshot(apps: [], commands: [planets, hidden]), isResident: true)
        var presented: [PanelRequest] = []
        let handler = IntentHandler.serving(model) { presented.append($0) }

        #expect(await handler.runnableCommands().map(\.id) == [planets.id], "a command switched off is not offered")
        handler.present(.show)
        #expect(presented == [.show])
        handler.recordUse(planets.id)
        #expect(usage.records[planets.id]?.count == 1)
    }
}
