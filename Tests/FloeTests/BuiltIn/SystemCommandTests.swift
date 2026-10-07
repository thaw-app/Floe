//
//  SystemCommandTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct SystemCommandTests {
    @Test(arguments: SystemCommand.allCases)
    func everyCommandHasATitleAndASymbolThatExists(command: SystemCommand) {
        #expect(!command.title.isEmpty)
        #expect(NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil) != nil)
    }

    @Test func onlyTheCommandsThatLoseWorkAskFirst() {
        let asking = Set(SystemCommand.allCases.filter { $0.confirmation != nil })
        #expect(asking == [.restart, .shutDown, .logOut, .emptyTrash, .quitAllApps])
    }

    @Test func onlyTheTogglesAnswerWithALineForTheHUD() {
        let toggles = Set(SystemCommand.allCases.filter { $0.flip != nil })
        #expect(toggles == [.toggleWiFi, .toggleMute, .volumeUp, .volumeDown, .toggleBluetooth, .ejectDisks, .toggleKeepAwake])
        #expect(toggles.allSatisfy { $0.confirmation == nil }, "a toggle is undone by running it again")
    }

    @Test(arguments: [
        ("wifi", "system:toggleWiFi"), ("unmute", "system:toggleMute"), ("prevent sleep", "system:toggleKeepAwake"),
        ("louder", "system:volumeUp"), ("quieter", "system:volumeDown"), ("bluetooth", "system:toggleBluetooth"), ("eject", "system:ejectDisks"),
    ])
    func aToggleIsFoundByWhatPeopleCallIt(query: String, id: String) {
        let results = Ranking.search(
            SystemCommand.allCases.map(RootItem.system), query: query, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }
        )
        #expect(results.first?.item.id == id)
    }

    @Test func aVolumeStepStopsAtSilenceAndAtFull() {
        #expect(SystemToggle.volume(0.5, steppedBy: SystemToggle.volumeStep) == 0.5625)
        #expect(SystemToggle.volume(0.5, steppedBy: -SystemToggle.volumeStep) == 0.4375)
        #expect(SystemToggle.volume(0.98, steppedBy: SystemToggle.volumeStep) == 1)
        #expect(SystemToggle.volume(0.02, steppedBy: -SystemToggle.volumeStep) == 0)
    }

    @Test(arguments: [
        (Bool?.some(true), false, false, false), (Bool?.some(false), false, false, true), (Bool?.some(true), true, false, true),
        (Bool?.some(true), false, true, true), (Bool?.none, false, false, false),
    ])
    func aDiskIsEjectedWhenItIsOutsideTheMacRemovableOrOnTheNetwork(isInternal: Bool?, isRemovable: Bool, isNetwork: Bool, ejected: Bool) {
        #expect(SystemToggle.isEjectable(isInternal: isInternal, isRemovable: isRemovable, isNetwork: isNetwork) == ejected)
    }

    @Test func theStartupDiskIsNeverAmongTheDisksToEject() {
        #expect(!SystemToggle.ejectableVolumes().contains { $0.path == "/" })
    }

    @Test func ejectingSaysHowManyWentOrWhichAreInUse() {
        #expect(SystemToggle.ejectSummary(ejected: 2, refused: []) == "Ejected disks: 2")
        #expect(SystemToggle.ejectSummary(ejected: 1, refused: ["Backup"]) == "Couldn't eject Backup")
    }

    @Test func keepAwakeHoldsUntilItIsFlippedBack() {
        #expect(!SystemToggle.isKeepingAwake)
        #expect(SystemToggle.flipKeepAwake() == "Keeping your Mac awake")
        #expect(SystemToggle.isKeepingAwake)
        #expect(SystemToggle.flipKeepAwake() == "Your Mac can sleep again")
        #expect(!SystemToggle.isKeepingAwake)
    }

    @Test func aKeywordFindsItsCommand() {
        let results = Ranking.search(
            SystemCommand.allCases.map(RootItem.system), query: "reboot", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }
        )
        #expect(results.first?.item.id == "system:restart")
    }
}
