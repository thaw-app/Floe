//
//  LauncherScreenTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct LauncherScreenTests {
    private let identifiers: [String?] = ["LEFT", "RIGHT", nil]
    private let frames = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800), CGRect(x: 2000, y: 0, width: 500, height: 800)]

    @Test func withNoChoiceTheLauncherOpensWhereThePointerIs() {
        #expect(LauncherScreen.choice(chosen: "", identifiers: identifiers, frames: frames, pointer: CGPoint(x: 1500, y: 400)) == 1)
        #expect(LauncherScreen.choice(chosen: "", identifiers: identifiers, frames: frames, pointer: CGPoint(x: 2200, y: 400)) == 2)
        #expect(LauncherScreen.choice(chosen: "", identifiers: identifiers, frames: frames, pointer: CGPoint(x: -50, y: 400)) == nil, "off every screen, the main one takes it")
    }

    @Test func aChosenScreenWinsWhereverThePointerIs() {
        #expect(LauncherScreen.choice(chosen: "LEFT", identifiers: identifiers, frames: frames, pointer: CGPoint(x: 1500, y: 400)) == 0)
    }

    @Test func aChosenScreenThatIsNotConnectedLeavesItToThePointer() {
        #expect(LauncherScreen.choice(chosen: "GONE", identifiers: identifiers, frames: frames, pointer: CGPoint(x: 1500, y: 400)) == 1)
    }

    @Test func screensOfTheSameModelAreNumbered() {
        let named = LauncherScreen.named([("A", "Studio Display"), ("B", "Built-in Display"), ("C", "Studio Display")])
        #expect(named.map(\.name) == ["Studio Display 1", "Built-in Display", "Studio Display 2"])
        #expect(named.map(\.id) == ["A", "B", "C"])
    }

    @Test func theScreenIsKeptButNotSynced() {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.launcherScreen.isEmpty)
        settings.launcherScreen = "LEFT"
        settings.save()
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).launcherScreen == "LEFT")
        #expect(!SettingsSync.synced.contains { $0.name == "launcherScreen" }, "a screen belongs to one Mac")
    }
}
