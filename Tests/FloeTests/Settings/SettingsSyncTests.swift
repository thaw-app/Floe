//
//  SettingsSyncTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The extensions one pretend Mac has, and the preferences it stores for them, in place of a scan and of files.
final class PretendExtensions {
    var commands: [ExtensionCommand] = []
    var stored: [String: [String: Any]] = [:]
}

/// One Mac's Floe: scratch settings and stores, and the sync service over a store in memory.
final class SyncedFloe {
    let scratch: ScratchDefaults
    let settings: AppSettings
    let snippets: SnippetStore
    let quicklinks: QuicklinkStore
    let store: MemorySyncStore
    let installed = PretendExtensions()
    let extensions: ExtensionSettingsSync
    let service: SettingsSyncService
    var time: TimeInterval = 1000
    private var journal: SyncJournal?

    init(cloud: MemorySyncCloud, folder: URL, name: String) throws {
        scratch = try ScratchDefaults()
        settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        snippets = SnippetStore(file: folder.appendingPathComponent("\(name)-snippets.json"))
        quicklinks = QuicklinkStore(file: folder.appendingPathComponent("\(name)-quicklinks.json"))
        let store = MemorySyncStore(cloud: cloud)
        self.store = store
        var journal: SyncJournal?
        var held: ExtensionSettingsSync.Held?
        let access = ExtensionSettingsSync.Access(
            includes: { [settings] in settings.syncsExtensionSettings },
            commands: { [installed] in installed.commands },
            stored: { [installed] in installed.stored[$0] ?? [:] },
            merge: { [installed] values, name in installed.stored[name, default: [:]].merge(values) { _, theirs in theirs } }
        )
        extensions = ExtensionSettingsSync(access: access, storage: .init(load: { held }, save: { held = $0 }))
        var clock: () -> TimeInterval = { 1000 }
        service = SettingsSyncService(
            settings: settings,
            snippets: snippets,
            quicklinks: quicklinks,
            extensions: extensions,
            storage: SyncJournalStorage(load: { journal }, save: { journal = $0 }),
            setup: SyncSetup(availability: SyncAvailability(isEntitled: { true }, hasAccount: { true }), makeStore: { store }),
            now: { Date(timeIntervalSince1970: clock()) }
        )
        clock = { [unowned self] in self.time }
    }

    /// Saves what was edited and lets the engine look, as the debounced observers do in the app.
    func changed(at time: TimeInterval) {
        self.time = time
        settings.save()
        service.engine.localChanged()
    }
}

struct SettingsSyncTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-sync-\(UUID().uuidString)")
    private let cloud = MemorySyncCloud()

    private func floe(_ name: String) throws -> SyncedFloe {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SyncedFloe(cloud: cloud, folder: folder, name: name)
    }

    @Test func everyStoredSettingIsOnOneSideOfTheTable() {
        let synced = SettingsSync.synced.map(\.name)
        let local = Set(SettingsSync.thisMacOnly.keys)
        let stored = Set(AppSettings.storedFields)
        #expect(stored.count > 50, "the stored settings were read")
        #expect(Set(synced).count == synced.count)
        #expect(Set(synced).isDisjoint(with: local))
        let unclassified = stored.subtracting(synced).subtracting(local)
        #expect(unclassified == [], "add each new setting to SettingsSync.synced or SettingsSync.thisMacOnly")
        let unknown = Set(synced).union(local).subtracting(stored)
        #expect(unknown == [], "the table names settings that are not stored")
    }

    @Test func whatMustStayOnThisMacIsNotAmongTheRecords() throws {
        let mac = try floe("a")
        mac.settings.notesFolder = "/Users/someone/Notes"
        mac.settings.lentSignIns = ["github-ext/github"]
        mac.settings.aiBaseURL = "https://api.example.com/v1"
        mac.settings.aiOnThisMacOnly = true
        mac.settings.indexesFileNames = true
        mac.settings.searchSources = ["files", "tabs"]
        mac.settings.fetchesExchangeRates = true
        mac.settings.focusShortcut = "Set Focus"
        mac.settings.showInDock = true
        mac.settings.diagnosticLogging = true
        mac.settings.syncsWithICloud = true
        mac.settings.shell.runs = false
        mac.snippets.expansionEnabled = false
        mac.settings.save()
        let records = SettingsSyncService.snapshot(settings: mac.settings, snippets: mac.snippets, quicklinks: mac.quicklinks)
        let fields = Set(records.keys.filter { $0.hasPrefix(SettingsSync.prefix) }.map { $0.dropFirst(2).prefix { $0 != "/" && $0 != "#" } }.map(String.init))
        #expect(fields.isSubset(of: Set(SettingsSync.synced.map(\.name))))
        #expect(records.keys.filter { $0.hasPrefix("s.shell") } == ["s.shell/prefix"])
        let everything = records.values.joined()
        for secret in ["someone", "github-ext", "api.example.com", "Set Focus"] {
            #expect(!everything.contains(secret))
        }
    }

    @Test func aFreshInstallOnTwoMacsHoldsTheSameRecords() throws {
        let a = try floe("a")
        let b = try floe("b")
        let records = SettingsSyncService.snapshot(settings: a.settings, snippets: a.snippets, quicklinks: a.quicklinks)
        #expect(records == SettingsSyncService.snapshot(settings: b.settings, snippets: b.snippets, quicklinks: b.quicklinks))
        #expect(records == SettingsSyncService.freshRecords(), "so a fresh install counts as untouched")
        #expect(records.keys.count { $0.hasPrefix("ql/") } == QuicklinkStore.defaults.count)
    }

    @Test func settingsChangedOnOneMacArriveOnTheOtherWithoutARestart() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        var told = 0
        b.settings.onSaved = { told += 1 }
        a.settings.aliases["app:/Applications/Safari.app"] = "saf"
        a.settings.commandHotkeys["sample/planets"] = KeyCombination(key: .space, modifiers: [.control])
        a.settings.launcherLayout = .compact
        a.settings.emojiSkinTone = .medium
        a.settings.shell.prefix = .dollar
        a.settings.toggleHotkey = nil
        a.changed(at: 2000)
        cloud.deliver()
        #expect(b.settings.aliases == ["app:/Applications/Safari.app": "saf"])
        #expect(b.settings.commandHotkeys == a.settings.commandHotkeys)
        #expect(b.settings.launcherLayout == .compact)
        #expect(b.settings.emojiSkinTone == .medium)
        #expect(b.settings.shell.prefix == .dollar)
        #expect(b.settings.toggleHotkey == nil)
        #expect(told == 1, "the settings process is told, as after any save")
        #expect(a.store.refusedKeys.isEmpty)
    }

    @Test func settingsOfThisMacStayWhenOthersArrive() throws {
        let a = try floe("a")
        let b = try floe("b")
        b.settings.notesFolder = "/Users/b/Notes"
        b.settings.shell.runs = false
        b.settings.disabledExtensions = ["weather"]
        b.settings.save()
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        a.settings.notesFolder = "/Users/a/Notes"
        a.settings.shell.prefix = .exclamation
        a.settings.popToRootDelay = 30
        a.changed(at: 2000)
        cloud.deliver()
        #expect(b.settings.popToRootDelay == 30)
        #expect(b.settings.shell.prefix == .exclamation)
        #expect(!b.settings.shell.runs)
        #expect(b.settings.notesFolder == "/Users/b/Notes")
        #expect(b.settings.disabledExtensions == ["weather"])
        #expect(!b.settings.syncsWithICloud, "the switch itself is never carried over")
    }

    @Test func twoMacsEditingDifferentAliasesBothKeepTheirs() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        b.store.isOnline = false
        a.settings.aliases["one"] = "1"
        a.changed(at: 2000)
        b.settings.aliases["two"] = "2"
        b.changed(at: 2100)
        b.store.isOnline = true
        cloud.deliver()
        #expect(a.settings.aliases == ["one": "1", "two": "2"])
        #expect(b.settings.aliases == ["one": "1", "two": "2"])
    }

    @Test func aRemovedAliasIsRemovedOnTheOtherMac() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.settings.aliases = ["one": "1", "two": "2"]
        a.settings.save()
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        cloud.deliver()
        #expect(b.settings.aliases.count == 2)
        b.settings.aliases["one"] = nil
        b.changed(at: 2000)
        cloud.deliver()
        #expect(a.settings.aliases == ["two": "2"])
    }

    @Test func favoritesAddedOnTwoMacsAreAllKeptAndTheLastOrderWins() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.settings.favorites = ["x", "y"]
        a.settings.save()
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        cloud.deliver()
        #expect(b.settings.favorites == ["x", "y"])
        b.store.isOnline = false
        a.settings.favorites = ["x", "y", "a"]
        a.changed(at: 2000)
        b.settings.favorites = ["b", "y", "x"]
        b.changed(at: 3000)
        b.store.isOnline = true
        cloud.deliver()
        #expect(a.settings.favorites == b.settings.favorites)
        #expect(b.settings.favorites == ["b", "y", "x", "a"], "the later order, then the favorite it did not know")
        a.settings.favorites.removeAll { $0 == "y" }
        a.changed(at: 4000)
        cloud.deliver()
        #expect(b.settings.favorites == ["b", "x", "a"])
    }

    @Test func snippetsAndQuicklinksTravelItemByItem() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        let greeting = Snippet(name: "Greeting", keyword: ";hi", text: "Hello there")
        a.snippets.upsert(greeting)
        a.quicklinks.add(Quicklink(name: "Docs", keyword: "docs", url: "https://example.com/?q={query}"))
        a.quicklinks.remove(QuicklinkStore.defaults[3])
        a.changed(at: 2000)
        cloud.deliver()
        #expect(b.snippets.snippets == [greeting])
        #expect(b.quicklinks.links == a.quicklinks.links)
        #expect(b.quicklinks.links.count == QuicklinkStore.defaults.count)
        b.store.isOnline = false
        b.snippets.upsert(Snippet(name: "Sign-off", keyword: ";bye", text: "Regards"))
        b.changed(at: 3000)
        var edited = greeting
        edited.text = "Hello again"
        a.snippets.upsert(edited)
        a.changed(at: 3100)
        b.store.isOnline = true
        cloud.deliver()
        #expect(a.snippets.snippets.map(\.keyword).sorted() == [";bye", ";hi"])
        #expect(b.snippets.snippets.first { $0.id == greeting.id }?.text == "Hello again")
        b.quicklinks.move(b.quicklinks.links[0], by: 2)
        b.changed(at: 4000)
        cloud.deliver()
        #expect(a.quicklinks.links == b.quicklinks.links, "the order travels too")
    }

    @Test func aRecordOfTheWrongTypeIsRefusedAndTheSettingKept() throws {
        let b = try floe("b")
        b.settings.aliases = ["kept": "k"]
        b.settings.save()
        b.store.plant(["t": 5000.0, "d": "x", "v": "7"], for: "s.aliases/bad")
        b.store.plant(["t": 5000.0, "d": "x", "v": "\"sideways\""], for: "s.launcherLayout")
        b.store.plant(["t": 5000.0, "d": "x", "v": "{\"name\":1}"], for: "snip/\(UUID().uuidString)")
        b.store.plant(["t": 5000.0, "d": "x", "v": "true"], for: "s.notesFolder")
        b.store.plant(["t": 5000.0, "d": "x", "v": "\"/Users/x\""], for: "s.shell/runs")
        b.store.plant(["t": 5000.0, "d": "x", "v": "\"fine\""], for: "s.aliases/good")
        b.service.engine.setOn(true)
        #expect(b.settings.aliases == ["kept": "k", "good": "fine"])
        #expect(b.settings.launcherLayout == .extended)
        #expect(b.snippets.snippets.isEmpty)
        #expect(b.settings.shell.runs)
        #expect(b.service.engine.status.skipped == 4, "a setting that stays on this Mac is left alone without counting")
    }

    @Test func removingFromICloudSwitchesTheSettingOff() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.settings.syncsWithICloud = true
        b.settings.syncsWithICloud = true
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        cloud.deliver()
        a.time = 5000
        a.service.engine.removeFromCloud()
        cloud.deliver()
        #expect(!a.settings.syncsWithICloud)
        #expect(!b.settings.syncsWithICloud)
    }

    @Test func openingThePanelLooksAtICloudAtMostOnceAMinute() throws {
        let mac = try floe("looks")
        mac.service.look()
        #expect(mac.store.exchanges == 0, "nothing is asked while sync is off")
        mac.settings.syncsWithICloud = true
        mac.service.engine.setOn(true)
        mac.time = 2000
        let before = mac.store.exchanges
        mac.service.look()
        mac.service.look()
        #expect(mac.store.exchanges == before + 1)
        mac.time = 2000 + SettingsSyncService.lookInterval
        mac.service.look()
        #expect(mac.store.exchanges == before + 2)
        mac.service.look(always: true)
        #expect(mac.store.exchanges == before + 3, "opening Settings always looks")
    }

    @Test func aHeavyUsersSettingsFitTheStoreWithRoomToSpare() throws {
        let mac = try floe("heavy")
        for index in 0 ..< 150 {
            mac.settings.aliases["app:/Applications/Some Application Number \(index).app"] = "alias\(index)"
        }
        for index in 0 ..< 60 {
            mac.settings.commandHotkeys["extension-name-\(index)/command-name"] = KeyCombination(key: .space, modifiers: [.control, .option])
            mac.settings.hiddenResults["app:/Applications/Hidden Application \(index).app"] = "Hidden Application \(index)"
        }
        mac.settings.favorites = (0 ..< 40).map { "app:/Applications/Favorite Application \($0).app" }
        mac.snippets.snippets = (0 ..< 200).map { Snippet(name: "Snippet number \($0)", keyword: ";snippet\($0)", text: String(repeating: "A line of text someone pastes often. ", count: 14)) }
        for index in 0 ..< 50 {
            mac.quicklinks.add(Quicklink(name: "Quicklink \(index)", keyword: "ql\(index)", url: "https://example.com/some/long/path/search?query={query}&index=\(index)"))
        }
        mac.settings.save()
        let fields = (0 ..< 6).map { Fixture.field("some-preference-\($0)") } + (0 ..< 4).map { Fixture.field("some-checkbox-\($0)", type: "checkbox") }
        for index in 0 ..< 40 {
            let name = "extension-name-\(index)"
            mac.installed.commands.append(Fixture.command("command-name", extension: name, extensionPreferences: fields))
            let texts = (0 ..< 6).map { ("some-preference-\($0)", "a value someone typed in" as Any) }
            mac.installed.stored[name] = Dictionary(uniqueKeysWithValues: texts + (0 ..< 4).map { ("some-checkbox-\($0)", true as Any) })
        }
        let extensionRecords = mac.extensions.records().mapValues { SyncRecord(value: $0, time: 1_760_000_000, device: UUID().uuidString) }
        let records = SettingsSyncService.snapshot(settings: mac.settings, snippets: mac.snippets, quicklinks: mac.quicklinks)
            .mapValues { SyncRecord(value: $0, time: 1_760_000_000, device: UUID().uuidString) }
            .merging(extensionRecords) { first, _ in first }
        let limits = SyncLimits.keyValueStore
        let size = limits.size(of: records)
        #expect(extensionRecords.count == 40, "one record for each extension, whatever it has of preferences")
        #expect(records.count == 627)
        #expect(limits.size(of: extensionRecords) < 40 * 600)
        #expect(records.count < limits.keys ?? 0)
        #expect(size < (limits.bytes ?? 0) / 3)
        #expect(limits.fits(records))
        let largest = records.map { SyncLimits.cloudKit.size(of: $0.value, key: $0.key) }.max() ?? 0
        #expect(largest < (SyncLimits.cloudKit.recordBytes ?? 0) / 100, "the other store limits one record, and none comes near")
        #expect(SyncLimits.cloudKit.fits(records))
    }

    @Test func theStatusLineSaysWhatIsGoingOn() {
        #expect(SettingsSyncText.line(for: SyncStatus(state: .off)) == "Sync is off.")
        #expect(SettingsSyncText.line(for: SyncStatus(state: .notSigned)) == "Unavailable: this build of Floe is not signed for iCloud.")
        #expect(SettingsSyncText.line(for: SyncStatus(state: .noAccount)) == "Unavailable: this Mac is not signed in to iCloud.")
        #expect(SettingsSyncText.line(for: SyncStatus(state: .full)) == "Floe's space in iCloud is full. Changes made on this Mac are not uploaded.")
        let viaDatabase = SettingsSyncText.line(for: SyncStatus(state: .full), backend: .cloudKit(container: "iCloud.example"))
        #expect(viaDatabase == "Your iCloud storage is full. Changes made on this Mac are not uploaded.")
        #expect(SettingsSyncText.line(for: SyncStatus(state: .off), backend: .cloudKit(container: "iCloud.example")) == "Sync is off.")
        #expect(SettingsSyncText.line(for: SyncStatus(state: .synced(Date(timeIntervalSince1970: 0)))).hasPrefix("Last synced "))
        #expect(SettingsSyncText.line(for: SyncStatus(state: .off, skipped: 2)).hasSuffix("2 entries in iCloud could not be read and were skipped."))
        #expect(SettingsSyncText.privacyLine(isOn: false, includesExtensions: true).hasPrefix("Settings sync is off"))
        #expect(SettingsSyncText.privacyLine(isOn: true, includesExtensions: false).contains("never sent"))
        #expect(!SettingsSyncText.privacyLine(isOn: true, includesExtensions: false).contains("extension"))
        #expect(SettingsSyncText.privacyLine(isOn: true, includesExtensions: true).contains("quicklinks and extension settings are kept"))
    }

    @Test func anOrderNeverAddsOrRemovesAMember() {
        #expect(OrderedSync.arranged(["a", "b", "c"], by: ["c", "gone", "a", "c"]) == ["c", "a", "b"])
        #expect(OrderedSync.arranged(["a", "b"], by: []) == ["a", "b"])
        #expect(OrderedSync.arranged([String](), by: ["a"]).isEmpty)
    }
}
