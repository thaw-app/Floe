//
//  SyncEngineTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// One Mac in a test: an app's values, a clock, a store in memory and the engine between them.
final class TestMac {
    var values: [String: String]
    var defaults: [String: String] = [:]
    var time: TimeInterval
    var isEntitled = true
    var hasAccount = true
    /// Keys the app will not take, as a real app refuses a value of the wrong type.
    var unacceptable: Set<String> = []
    /// What the app holds after taking a value in. An app that knows the whole value keeps it as it came.
    var kept: (String) -> String = { $0 }
    private(set) var applied: [[String: String]] = []
    private(set) var storesMade = 0
    private(set) var timesTurnedOff = 0
    private(set) var statuses: [SyncStatus] = []
    private var saved: SyncJournal?
    let store: MemorySyncStore
    let name: String
    private(set) lazy var engine = makeEngine()

    init(_ name: String, cloud: MemorySyncCloud?, values: [String: String] = [:], time: TimeInterval = 1000) {
        self.name = name
        self.values = values
        self.time = time
        store = MemorySyncStore(cloud: cloud)
    }

    /// A new engine over the same app, journal and store: the app after a restart.
    func makeEngine() -> SyncEngine {
        let client = SyncClient(
            snapshot: { [unowned self] in self.values },
            defaults: defaults,
            apply: { [unowned self] changed, removed in
                let taken = changed.filter { !self.unacceptable.contains($0.key) }
                self.applied.append(taken)
                self.values.merge(taken.mapValues(self.kept)) { _, new in new }
                removed.forEach { self.values[$0] = nil }
                return Set(changed.keys).intersection(self.unacceptable)
            },
            turnOff: { [unowned self] in self.timesTurnedOff += 1 }
        )
        let engine = SyncEngine(
            client: client,
            storage: SyncJournalStorage(load: { [unowned self] in self.saved }, save: { [unowned self] in self.saved = $0 }),
            availability: SyncAvailability(isEntitled: { [unowned self] in self.isEntitled }, hasAccount: { [unowned self] in self.hasAccount }),
            makeStore: { [unowned self] in
                self.storesMade += 1
                return self.store
            },
            now: { [unowned self] in Date(timeIntervalSince1970: self.time) },
            device: { [name] in name }
        )
        engine.onStatusChange = { [unowned self] in self.statuses.append($0) }
        return engine
    }

    /// The app changes a value, or removes it, and the engine hears of it a moment later.
    func edit(_ key: String, _ value: String?, at time: TimeInterval? = nil) {
        if let time {
            self.time = time
        }
        values[key] = value
        engine.localChanged()
    }
}

struct SyncEngineTests {
    private let cloud = MemorySyncCloud()

    private func mac(_ name: String, values: [String: String] = [:], time: TimeInterval = 1000) -> TestMac {
        TestMac(name, cloud: cloud, values: values, time: time)
    }

    @Test func nothingIsWrittenWhileSyncIsOff() {
        let a = mac("a", values: ["alias": "\"s\""])
        a.engine.setOn(false)
        a.edit("alias", "\"saf\"", at: 2000)
        #expect(a.store.all().isEmpty)
        #expect(a.engine.status.state == .off)
        #expect(a.engine.journal.records["alias"]?.time == 2000, "the change is still dated, for the day sync is switched on")
    }

    @Test func anEditOnOneMacArrivesOnTheOther() {
        let a = mac("a")
        let b = mac("b")
        a.engine.setOn(true)
        b.engine.setOn(true)
        a.edit("alias", "\"saf\"", at: 2000)
        cloud.deliver()
        #expect(b.values == ["alias": "\"saf\""])
        #expect(b.engine.status.state == .synced(Date(timeIntervalSince1970: 1000)))
    }

    @Test func aReceivedChangeIsNotSentBackAsANewOne() {
        let a = mac("a")
        let b = mac("b")
        a.engine.setOn(true)
        b.engine.setOn(true)
        a.edit("alias", "\"saf\"", at: 2000)
        cloud.deliver()
        let held = a.store.all() as NSDictionary
        b.time = 3000
        b.engine.localChanged()
        cloud.deliver()
        #expect(a.store.all() as NSDictionary == held, "the record still carries the first Mac's stamp")
        #expect(a.applied.isEmpty)
        #expect(b.engine.journal.records["alias"] == SyncRecord(value: "\"saf\"", time: 2000, device: "a"))
    }

    @Test func aValueTheAppKeepsOnlyPartOfIsNotSentBackEither() {
        let a = mac("a")
        let b = mac("b")
        // An older version that drops a field it does not know: what it holds afterwards differs from the record.
        b.kept = { _ in "{\"alpha\":1}" }
        a.engine.setOn(true)
        b.engine.setOn(true)
        a.edit("tint", "{\"alpha\":1,\"new\":true}", at: 2000)
        cloud.deliver()
        #expect(b.values["tint"] == "{\"alpha\":1}")
        b.time = 3000
        b.engine.localChanged()
        cloud.deliver()
        #expect(a.values["tint"] == "{\"alpha\":1,\"new\":true}", "the newer version's field is still there")
        #expect(b.engine.journal.records["tint"]?.device == "a")
    }

    @Test func aDeletionIsNotBroughtBackByAnotherMac() {
        let a = mac("a", values: ["snippet": "\"hi\""])
        let b = mac("b", values: ["snippet": "\"hi\""])
        a.engine.setOn(true)
        b.engine.setOn(true)
        cloud.deliver()
        a.edit("snippet", nil, at: 2000)
        cloud.deliver()
        #expect(b.values["snippet"] == nil)
        b.time = 3000
        b.engine.localChanged()
        cloud.deliver()
        #expect(a.values["snippet"] == nil)
    }

    @Test func aMacThatWasOfflineDoesNotUndoANewerChange() {
        let a = mac("a", values: ["alias": "\"one\""])
        let b = mac("b", values: ["alias": "\"one\""])
        a.engine.setOn(true)
        b.engine.setOn(true)
        cloud.deliver()
        b.store.isOnline = false
        b.edit("alias", "\"offline\"", at: 2000)
        a.edit("alias", "\"later\"", at: 3000)
        b.store.isOnline = true
        cloud.deliver()
        #expect(a.values["alias"] == "\"later\"")
        #expect(b.values["alias"] == "\"later\"")
    }

    @Test func switchingOnMergesWhatBothSidesAlreadyHold() {
        let a = mac("a")
        a.edit("alias/a", "\"a\"", at: 100)
        a.edit("layout", "\"compact\"", at: 200)
        let b = mac("b")
        b.edit("alias/b", "\"b\"", at: 150)
        b.edit("layout", "\"extended\"", at: 300)
        a.engine.setOn(true)
        cloud.deliver()
        b.engine.setOn(true)
        cloud.deliver()
        let merged = ["alias/a": "\"a\"", "alias/b": "\"b\"", "layout": "\"extended\""]
        #expect(a.values == merged)
        #expect(b.values == merged, "nothing here was deleted because iCloud lacked it")
    }

    @Test func aSettingStillAtItsDefaultLosesToAnyChange() {
        let a = mac("a", values: ["layout": "\"compact\""], time: 500)
        a.defaults = ["layout": "\"extended\""]
        a.engine.setOn(true)
        let b = mac("b", values: ["layout": "\"extended\""], time: 9000)
        b.defaults = ["layout": "\"extended\""]
        b.engine.setOn(true)
        cloud.deliver()
        #expect(b.values["layout"] == "\"compact\"", "a new Mac's untouched default does not replace the other Mac's choice")
        #expect(a.values["layout"] == "\"compact\"")
    }

    @Test func aFreshMacDoesNotUploadDefaultsBeforeTheFirstDownload() {
        let a = mac("a", values: ["layout": "\"compact\""], time: 500)
        a.defaults = ["layout": "\"extended\""]
        a.engine.setOn(true)
        a.store.isOnline = false

        let b = mac("b", values: ["layout": "\"extended\""], time: 9000)
        b.defaults = a.defaults
        b.engine.setOn(true)
        cloud.deliver()
        #expect(b.values["layout"] == "\"compact\"")
        let c = mac("c")
        c.engine.setOn(true)
        cloud.deliver()
        #expect(c.values["layout"] == "\"compact\"", "the original cloud value survived without Mac A repairing it")
    }

    @Test func anExplicitChangeBackToTheDefaultStillUploads() {
        let a = mac("a", values: ["layout": "\"extended\""])
        a.defaults = a.values
        a.engine.setOn(true)
        #expect(a.store.all().isEmpty, "untouched defaults stay local even when the cloud is empty")
        a.edit("layout", "\"compact\"", at: 2000)
        a.edit("layout", "\"extended\"", at: 3000)
        let b = mac("b")
        b.engine.setOn(true)
        cloud.deliver()
        #expect(b.values["layout"] == "\"extended\"")
        #expect(b.engine.journal.records["layout"]?.time == 3000)
    }

    @Test func anEditMadeAfterSeeingARecordWinsOverAFastClock() {
        let a = mac("a")
        let b = mac("b")
        a.engine.setOn(true)
        b.engine.setOn(true)
        a.edit("alias", "\"future\"", at: 900_000)
        cloud.deliver()
        b.edit("alias", "\"mine\"", at: 2000)
        cloud.deliver()
        #expect(a.values["alias"] == "\"mine\"")
        #expect(b.values["alias"] == "\"mine\"")
    }

    @Test func switchingOffStopsTheExchangeAndKeepsBothCopies() {
        let a = mac("a")
        let b = mac("b")
        a.engine.setOn(true)
        b.engine.setOn(true)
        a.edit("alias", "\"saf\"", at: 2000)
        cloud.deliver()
        b.engine.setOn(false)
        let held = b.store.all() as NSDictionary
        a.edit("alias", "\"safari\"", at: 3000)
        b.edit("other", "1", at: 3500)
        cloud.deliver()
        #expect(b.values["alias"] == "\"saf\"")
        #expect(a.values["other"] == nil)
        #expect(!(held.allKeys.isEmpty))
        #expect(b.engine.status.state == .off)
    }

    @Test func garbageInTheStoreIsSkippedAndCounted() {
        let a = mac("a")
        a.store.plant("not a record", for: "s.alias")
        a.store.plant(["t": "yesterday", "d": "x", "v": "1"], for: "s.time")
        a.store.plant(["t": 5.0, "d": "x", "v": "{not json"], for: "s.value")
        a.store.plant(["t": 5.0, "d": "x", "v": 7], for: "s.number")
        a.store.plant(["t": 5.0, "d": "x", "v": "\"fine\""], for: "s.fine")
        a.engine.setOn(true)
        #expect(a.values == ["s.fine": "\"fine\""])
        #expect(a.engine.status.skipped == 4)
        #expect(a.store.all().count == 5, "what could not be read is left alone")
    }

    @Test func aRecordTheAppRefusesIsCountedAndLeftAlone() {
        let a = mac("a")
        let b = mac("b", values: ["alias": "\"mine\""], time: 10)
        b.unacceptable = ["alias"]
        b.engine.localChanged()
        a.engine.setOn(true)
        a.edit("alias", "7", at: 2000)
        b.engine.setOn(true)
        cloud.deliver()
        #expect(b.values["alias"] == "\"mine\"")
        #expect(b.engine.status.skipped == 1)
        #expect(a.values["alias"] == "7", "the refusing Mac does not overwrite the record it could not read")
        b.edit("alias", "\"repaired\"", at: 3000)
        cloud.deliver()
        #expect(a.values["alias"] == "\"repaired\"")
        #expect(b.engine.status.skipped == 0)
    }

    @Test func aKeyLongerThanTheStoreTakesStillTravels() {
        let key = "s.aliases/app:/Applications/" + String(repeating: "Long Name ", count: 12) + ".app"
        let a = mac("a")
        let b = mac("b")
        a.engine.setOn(true)
        b.engine.setOn(true)
        a.edit(key, "\"long\"", at: 2000)
        cloud.deliver()
        #expect(a.store.refusedKeys.isEmpty)
        #expect(b.values == [key: "\"long\""])
    }

    @Test func aStoreThatWouldOverflowIsNotWrittenAndTheStatusSaysSo() {
        let a = mac("a")
        a.engine.setOn(true)
        a.edit("small", "1", at: 2000)
        a.edit("huge", "\"" + String(repeating: "x", count: SyncWire.byteBudget) + "\"", at: 3000)
        #expect(a.engine.status.state == .full)
        #expect(a.store.all().keys.sorted() == ["small"])
        a.edit("huge", nil, at: 4000)
        #expect(a.engine.status.state == .synced(Date(timeIntervalSince1970: 4000)))
    }

    @Test func tooManyKeysCountAsFullToo() {
        let a = mac("a")
        for index in 0 ... SyncWire.keyBudget {
            a.values["k\(index)"] = "1"
        }
        a.engine.setOn(true)
        #expect(a.engine.status.state == .full)
        #expect(a.store.all().isEmpty)
    }

    @Test func aBuildWithoutTheEntitlementNeverTouchesTheStore() {
        let a = mac("a")
        a.isEntitled = false
        a.engine.setOn(true)
        a.edit("alias", "\"saf\"")
        a.engine.removeFromCloud()
        #expect(a.storesMade == 0)
        #expect(a.engine.status.state == .notSigned)
    }

    @Test func withoutAnAccountNothingIsExchanged() {
        let a = mac("a")
        a.hasAccount = false
        a.engine.setOn(true)
        a.edit("alias", "\"saf\"")
        #expect(a.engine.status.state == .noAccount)
        #expect(a.store.all().isEmpty)
        a.hasAccount = true
        a.store.onExternalChange?(.account)
        #expect(a.store.all().count == 1)
    }

    @Test func removingFromICloudEmptiesTheStoreAndSwitchesEveryMacOff() {
        let a = mac("a", values: ["alias": "\"a\""])
        let b = mac("b", values: ["other": "\"b\""])
        a.engine.setOn(true)
        b.engine.setOn(true)
        cloud.deliver()
        a.time = 5000
        a.engine.removeFromCloud()
        cloud.deliver()
        #expect(a.store.all().keys.sorted() == [SyncEngine.clearedKey])
        #expect(b.store.all().keys.sorted() == [SyncEngine.clearedKey], "the other Mac did not put its copy back")
        #expect(a.timesTurnedOff == 1)
        #expect(b.timesTurnedOff == 1)
        #expect(b.engine.status.state == .off)
        #expect(a.values == ["alias": "\"a\"", "other": "\"b\""], "each Mac keeps its settings")
        #expect(b.values == ["alias": "\"a\"", "other": "\"b\""])
    }

    @Test func aFastClockDoesNotIgnoreARemovalMadeAfterJoining() {
        let a = mac("a", values: ["alias": "\"a\""], time: 1000)
        let b = mac("b", time: 1300)
        a.engine.setOn(true)
        b.engine.setOn(true)
        cloud.deliver()
        a.time = 1100
        a.engine.removeFromCloud()
        cloud.deliver()
        #expect(!b.engine.isOn)
        #expect(b.timesTurnedOff == 1)
        #expect(a.store.all().keys.sorted() == [SyncEngine.clearedKey])
        #expect(b.store.all().keys.sorted() == [SyncEngine.clearedKey])
    }

    @Test func syncCanBeSwitchedOnAgainAfterARemoval() {
        let a = mac("a", values: ["alias": "\"a\""])
        a.engine.setOn(true)
        a.time = 5000
        a.engine.removeFromCloud()
        a.time = 6000
        a.engine.setOn(true)
        #expect(a.engine.status.state == .synced(Date(timeIntervalSince1970: 6000)))
        #expect(a.store.all().count == 2)
        let later = mac("later", time: 7000)
        later.engine.setOn(true)
        cloud.deliver()
        #expect(later.timesTurnedOff == 0, "a removal made before this Mac joined is not meant for it")
        #expect(later.values == ["alias": "\"a\""])
    }

    @Test func aRestartDoesNotTreatAnUnseenRemovalAsPermissionToRejoin() {
        let a = mac("a", values: ["alias": "\"a\""], time: 1000)
        a.engine.setOn(true)
        cloud.deliver()
        let restarted = a.makeEngine()
        let clear = SyncRecord(value: nil, time: 1100, device: "b")
        a.store.plant(SyncWire.encode(clear, key: SyncEngine.clearedKey), for: SyncEngine.clearedKey)
        restarted.setOn(true)
        #expect(!restarted.isOn)
        #expect(a.timesTurnedOff == 1)
        a.store.onExternalChange?(.initialValues)
        #expect(!restarted.isOn)
    }

    @Test func aDeliberateJoinAcceptsAnOldClearEvenWithASlowerClock() {
        let a = mac("a", values: ["alias": "\"a\""], time: 5000)
        a.engine.setOn(true)
        a.engine.removeFromCloud()
        let b = mac("b", time: 1000)
        b.engine.setOn(true)
        cloud.deliver()
        #expect(b.engine.isOn)
        #expect(b.timesTurnedOff == 0)
        #expect(b.engine.journal.clearedAt == a.engine.journal.clearedAt)

        // A later removal is acted on even if it arrives as another initial download notification.
        let clear = SyncRecord(value: nil, time: 6000, device: "a")
        b.store.plant(SyncWire.encode(clear, key: SyncEngine.clearedKey), for: SyncEngine.clearedKey)
        b.store.onExternalChange?(.initialValues)
        #expect(!b.engine.isOn)
        #expect(b.timesTurnedOff == 1)
    }

    @Test func oldRemovalsLeaveTheJournalAndTheStore() {
        let a = mac("a", values: ["alias": "\"a\""])
        a.engine.setOn(true)
        a.edit("alias", nil, at: 2000)
        #expect(a.store.all().count == 1)
        a.time = 2000 + SyncMerge.removalLifetime + 1
        a.engine.refresh()
        #expect(a.store.all().isEmpty)
        #expect(a.engine.journal.records.isEmpty)
    }

    @Test func theJournalSurvivesARestart() {
        let a = mac("a")
        a.engine.setOn(true)
        a.edit("alias", "\"saf\"", at: 2000)
        let restarted = a.makeEngine()
        #expect(restarted.journal == a.engine.journal)
        #expect(restarted.journal.device == "a")
        #expect(restarted.journal.wasOn)
    }

    @Test func theStatusCrossesToAnotherProcessAsText() {
        let all: [SyncStatus] = [
            SyncStatus(state: .off), SyncStatus(state: .notSigned), SyncStatus(state: .noAccount), SyncStatus(state: .syncing),
            SyncStatus(state: .synced(Date(timeIntervalSince1970: 1_760_000_000.5)), skipped: 3), SyncStatus(state: .full, skipped: 1),
        ]
        for status in all {
            #expect(SyncStatus(text: status.text) == status)
        }
        for text in ["", "off", "synced@soon;0", "on;0", "off;-1", "off;0;0"] {
            #expect(SyncStatus(text: text) == nil)
        }
    }

    @Test func theSystemReasonsBecomeStoreChanges() {
        #expect(UbiquitousSyncStore.change(reason: NSUbiquitousKeyValueStoreQuotaViolationChange) == .overQuota)
        #expect(UbiquitousSyncStore.change(reason: NSUbiquitousKeyValueStoreAccountChange) == .account)
        #expect(UbiquitousSyncStore.change(reason: NSUbiquitousKeyValueStoreServerChange) == .values)
        #expect(UbiquitousSyncStore.change(reason: NSUbiquitousKeyValueStoreInitialSyncChange) == .initialValues)
        #expect(UbiquitousSyncStore.change(reason: nil) == .values)
    }
}
