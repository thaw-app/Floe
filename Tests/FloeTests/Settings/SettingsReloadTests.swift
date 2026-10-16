//
//  SettingsReloadTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Two `AppSettings` on one scratch defaults stand for the launcher and its settings process.
struct SettingsReloadTests {
    private let scratch: ScratchDefaults
    private let launcher: AppSettings
    private let window: AppSettings

    init() throws {
        scratch = ScratchDefaults()
        // Saved by hand, so no test depends on when the debounced save would have run.
        launcher = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        window = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
    }

    @Test func aReloadTakesWhatTheOtherProcessSaved() {
        window.launcherLayout = .compact
        window.aliases["sample/planets"] = "pl"
        window.disabledExtensions = ["weather"]
        window.toggleHotkey = nil
        window.save()

        launcher.reload()
        #expect(launcher.launcherLayout == .compact)
        #expect(launcher.aliases == ["sample/planets": "pl"])
        #expect(launcher.disabledExtensions == ["weather"])
        #expect(launcher.toggleHotkey == nil)
    }

    @Test func aReloadIsNotAnEditSoNothingEchoesBack() {
        var launcherSaves = 0
        launcher.onSaved = { launcherSaves += 1 }
        window.popToRootDelay = 30
        window.save()

        launcher.reload()
        #expect(launcher.popToRootDelay == 30)
        #expect(!launcher.hasUnsavedChanges, "taking stored values schedules no save")
        launcher.save()
        #expect(launcherSaves == 0, "saving what is already stored tells nobody")
    }

    @Test func aSaveIsAnnouncedOnceAndOnlyWhenItChangedSomething() {
        var saves = 0
        window.onSaved = { saves += 1 }
        window.showInDock = true
        #expect(window.hasUnsavedChanges)
        window.save()
        #expect(saves == 1)
        #expect(!window.hasUnsavedChanges)
        window.save()
        #expect(saves == 1)
    }

    @Test func aReloadWithNothingNewLeavesEverythingAlone() {
        launcher.rememberMenuBarQuery = true
        launcher.reload()
        #expect(launcher.rememberMenuBarQuery, "nothing was stored yet, so there is nothing to take")
        #expect(launcher.hasUnsavedChanges)
    }

    @Test func aSaveKeepsWhatTheOtherProcessChangedMeanwhile() {
        window.searchSources = ["browser-tabs"]
        window.save()
        // The launcher never heard about it and saves a change of its own.
        launcher.favorites = ["command:sample/planets"]
        launcher.save()

        #expect(launcher.searchSources == ["browser-tabs"], "the save took in what was stored first")
        let fresh = AppSettings(defaults: scratch.defaults)
        #expect(fresh.searchSources == ["browser-tabs"])
        #expect(fresh.favorites == ["command:sample/planets"])
    }

    @Test func anEditWaitingToBeSavedSurvivesAReload() {
        var launcherSaves = 0
        launcher.onSaved = { launcherSaves += 1 }
        launcher.menuBarCommands = ["weather/menu"]
        window.clipboardHistoryEnabled = false
        window.save()

        launcher.reload()
        #expect(launcher.menuBarCommands == ["weather/menu"])
        #expect(!launcher.clipboardHistoryEnabled)
        #expect(launcherSaves == 1, "the waiting edit went out with the reload")

        window.reload()
        #expect(window.menuBarCommands == ["weather/menu"])
        #expect(!window.clipboardHistoryEnabled)
    }

    @Test func whenBothChangedTheSameSettingTheUnsavedEditWins() {
        launcher.popToRootDelay = 300
        window.popToRootDelay = 30
        window.save()
        launcher.reload()
        #expect(launcher.popToRootDelay == 300)
        #expect(AppSettings(defaults: scratch.defaults).popToRootDelay == 300)
    }

    @Test func anImportReachesTheOtherProcess() throws {
        let other = ScratchDefaults()
        let source = AppSettings(defaults: other.defaults, savesAfterEdits: false)
        source.aliases = ["sample/planets": "p"]
        source.launcherShowsShadow = true
        let exported = try source.exportedJSON()

        var saves = 0
        window.onSaved = { saves += 1 }
        try window.importJSON(exported)
        #expect(saves == 1)
        launcher.reload()
        #expect(launcher.aliases == ["sample/planets": "p"])
        #expect(launcher.launcherShowsShadow)
    }
}

struct SettingsMergeTests {
    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func keyOrderDoesNotMakeTwoBlobsDiffer() {
        let left = Data(#"{"a":1,"b":[1,2]}"#.utf8)
        let right = Data(#"{"b":[1,2],"a":1}"#.utf8)
        #expect(SettingsMerge.isSame(left, right))
        #expect(!SettingsMerge.isSame(left, Data(#"{"a":2,"b":[1,2]}"#.utf8)))
        #expect(SettingsMerge.isSame(nil, nil))
        #expect(!SettingsMerge.isSame(left, nil))
    }

    @Test func eachSidesChangesAreKept() throws {
        let base = try json(["a": 1, "b": 1, "c": 1])
        let mine = try json(["a": 2, "b": 1, "c": 1])
        let theirs = try json(["a": 1, "b": 2, "c": 1])
        #expect(try object(SettingsMerge.merged(base: base, mine: mine, theirs: theirs)) == ["a": 2, "b": 2, "c": 1])
    }

    @Test func aKeyChangedOnBothSidesKeepsMine() throws {
        let merged = try SettingsMerge.merged(base: json(["a": 1]), mine: json(["a": 2]), theirs: json(["a": 3]))
        #expect(try object(merged) == ["a": 2])
    }

    @Test func aKeyTheOtherSideRemovedOrAddedFollows() throws {
        let base = try json(["a": 1, "gone": true])
        let mine = try json(["a": 1, "gone": true])
        let theirs = try json(["a": 1, "new": "x"])
        #expect(try object(SettingsMerge.merged(base: base, mine: mine, theirs: theirs)) == ["a": 1, "new": "x"])
    }
}

/// The stores Settings edits in files: the other process reads them again without saving them back.
struct StoreReloadTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-tests-\(UUID().uuidString)")

    @Test func snippetsSavedByOneProcessAreReadByTheOther() {
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("snippets.json")
        let window = SnippetStore(file: file)
        let launcher = SnippetStore(file: file)
        var windowSaves = 0
        var launcherSaves = 0
        window.onSaved = { windowSaves += 1 }
        launcher.onSaved = { launcherSaves += 1 }

        window.upsert(Snippet(name: "Signature", keyword: ";sig", text: "Regards"))
        window.expansionEnabled = false
        #expect(windowSaves == 2)

        launcher.reload()
        #expect(launcher.snippets.map(\.keyword) == [";sig"])
        #expect(!launcher.expansionEnabled)
        #expect(launcherSaves == 0, "a reload writes nothing, so nothing echoes back")
    }

    @Test func quicklinksSavedByOneProcessAreReadByTheOther() {
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("quicklinks.json")
        let window = QuicklinkStore(file: file)
        let launcher = QuicklinkStore(file: file)
        var launcherSaves = 0
        launcher.onSaved = { launcherSaves += 1 }
        #expect(launcher.links == QuicklinkStore.defaults)

        window.add(Quicklink(name: "Example", keyword: "ex", url: "https://example.com/?q={query}"))
        launcher.reload()
        #expect(launcher.links.last?.keyword == "ex")
        #expect(launcher.links.count == QuicklinkStore.defaults.count + 1)
        #expect(launcherSaves == 0)
    }

    @Test func aQuicklinkReloadWithoutAFileKeepsWhatIsThere() {
        let launcher = QuicklinkStore(file: folder.appendingPathComponent("missing.json"))
        launcher.reload()
        #expect(launcher.links == QuicklinkStore.defaults)
    }
}

struct ThawStatusMirrorTests {
    @Test func theSettingsProcessShowsTheLaunchersStatusAndItsSavedAnswers() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        var environment = ThawAppearanceFollower.Environment.live
        environment.open = { _ in
            Issue.record("the settings process never asks Thaw itself")
            return false
        }
        let follower = ThawAppearanceFollower(settings: settings, defaults: scratch.defaults, environment: environment)
        #expect(follower.status == .idle)
        follower.mirror(.notRunning)
        #expect(follower.status == .notRunning)
        for status in [ThawAppearanceFollower.Status.idle, .following, .noAnswer, .notRunning, .unreadable] {
            #expect(ThawAppearanceFollower.Status(rawValue: status.rawValue) == status)
        }
    }
}
