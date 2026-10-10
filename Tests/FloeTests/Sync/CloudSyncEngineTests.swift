//
//  CloudSyncEngineTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// A stand-in for CloudKit's server: one zone of records, each with a tag that changes on every save.
/// It behaves as the documentation says the real one does, which is not the same as being the real one.
final class PretendServer {
    fileprivate var records: [String: CloudSyncEntry] = [:]
    fileprivate var zoneExists = false
    /// Counts the zone's deletions, so a store notices one made by another.
    fileprivate var generation = 0
    private var tag = 0
    var hasRoom = true
    fileprivate var stores: [PretendCloudStore] = []

    var names: [String] {
        records.keys.sorted()
    }

    /// Lets every online store fetch and send, until none has anything left to say.
    func deliver() {
        for _ in 0 ..< 10 {
            stores.filter(\.isOnline).forEach { $0.synchronize() }
        }
    }

    /// The user deletes the app's data in iCloud's settings.
    func purge() {
        records = [:]
        zoneExists = false
        generation += 1
        stores.forEach { $0.purged = true }
    }

    fileprivate func nextTag() -> Data {
        tag += 1
        return Data("\(tag)".utf8)
    }
}

/// The CloudKit store with the pretend server in place of the system's sync engine: the same core, the same commands.
final class PretendCloudStore: SyncStore {
    private(set) var core: CloudSyncCore
    private let server: PretendServer
    private var queue: [CloudSyncCommand] = []
    private var generation: Int?
    fileprivate var purged = false
    var isOnline = true
    var onExternalChange: ((SyncStoreChange) -> Void)?

    var limits: SyncLimits {
        core.limits
    }

    init(server: PretendServer, mirror: SyncMirror? = nil, hasSavedState: Bool = false) {
        self.server = server
        core = CloudSyncCore(mirror: mirror, hasSavedState: hasSavedState)
        server.stores.append(self)
    }

    func all() -> [String: Any] {
        core.contents
    }

    func set(_ value: [String: Any], for key: String) {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys)) ?? Data()
        run(core.set(String(decoding: data, as: UTF8.self), for: key))
    }

    func remove(_ key: String) {
        run(core.remove(key))
    }

    func removeAll() {
        run(core.removeAll())
    }

    @discardableResult
    func synchronize() -> Bool {
        guard isOnline else { return false }
        run(core.resend())
        fetch()
        send()
        return true
    }

    /// A new store in this one's place. Without the saved state the fetch starts from nothing, as the real one does.
    func relaunched(keepingMirror: Bool, keepingState: Bool) -> PretendCloudStore {
        server.stores.removeAll { $0 === self }
        let next = PretendCloudStore(server: server, mirror: keepingMirror ? core.mirror : nil, hasSavedState: keepingState)
        next.generation = next.core.keepsSavedState ? generation : nil
        return next
    }

    func account(_ event: CloudSyncEvent) {
        take(event)
    }

    private func take(_ event: CloudSyncEvent) {
        let effects = core.handle(event)
        run(effects.commands)
        if let change = effects.change {
            onExternalChange?(change)
        }
    }

    private func run(_ commands: [CloudSyncCommand]) {
        for command in commands {
            switch command {
            case let .forget(name): queue.removeAll { $0 == .save(name) || $0 == .delete(name) }
            case .forgetEverything: queue = []
            case .restart:
                queue = []
                generation = nil
            case .fetch: break
            default:
                if !queue.contains(command) {
                    queue.append(command)
                }
            }
        }
    }

    private func fetch() {
        if purged {
            purged = false
            generation = server.generation
            take(.zoneLost(.purged))
        } else if let generation, generation != server.generation {
            take(.zoneLost(.deleted))
        }
        generation = server.generation
        let known = core.mirror.server
        let changed = server.records.filter { known[$0.key]?.system != $0.value.system }
        let deleted = known.keys.filter { server.records[$0] == nil }
        if !changed.isEmpty || !deleted.isEmpty {
            take(.fetched(changed: changed, deleted: Array(deleted)))
        }
        take(.fetchFinished)
    }

    private func send() {
        for _ in 0 ..< 10 where !queue.isEmpty {
            let batch = queue
            queue = []
            sendZoneChanges(batch)
            var saved: [String: CloudSyncEntry] = [:]
            var deleted: [String] = []
            var failed: [String: CloudSyncFailure] = [:]
            for case let .save(name) in batch {
                guard let entry = core.outgoing(name) else { continue }
                if let failure = refusal(of: entry, named: name) {
                    failed[name] = failure
                } else {
                    saved[name] = CloudSyncEntry(json: entry.json, system: server.nextTag())
                    server.records[name] = saved[name]
                }
            }
            for case let .delete(name) in batch {
                server.records[name] = nil
                deleted.append(name)
            }
            if !saved.isEmpty || !deleted.isEmpty || !failed.isEmpty {
                take(.sent(saved: saved, deleted: deleted, failedSaves: failed, failedDeletes: [:]))
            }
        }
    }

    private func sendZoneChanges(_ batch: [CloudSyncCommand]) {
        if batch.contains(.deleteZone) {
            server.records = [:]
            server.zoneExists = false
            server.generation += 1
            generation = server.generation
            take(.zoneDeletionSent)
        }
        if batch.contains(.saveZone) {
            server.zoneExists = true
            take(.zoneSaved)
        }
    }

    private func refusal(of entry: CloudSyncEntry, named name: String) -> CloudSyncFailure? {
        guard server.zoneExists else { return .zoneMissing }
        guard server.hasRoom else { return .quotaExceeded }
        if let held = server.records[name] {
            return held.system == entry.system ? nil : .conflict(held)
        }
        return entry.system == nil ? nil : .unknownItem
    }
}

/// One Mac whose engine syncs through the pretend server.
final class CloudMac {
    var values: [String: String]
    var time: TimeInterval
    var hasAccount = true
    private(set) var timesTurnedOff = 0
    private var journal: SyncJournal?
    private(set) var store: PretendCloudStore
    private(set) lazy var engine = makeEngine()

    private func makeEngine() -> SyncEngine {
        SyncEngine(
            client: SyncClient(
                snapshot: { [unowned self] in self.values },
                apply: { [unowned self] changed, removed in
                    self.values.merge(changed) { _, new in new }
                    removed.forEach { self.values[$0] = nil }
                    return []
                },
                turnOff: { [unowned self] in self.timesTurnedOff += 1 }
            ),
            storage: SyncJournalStorage(load: { [unowned self] in self.journal }, save: { [unowned self] in self.journal = $0 }),
            availability: SyncAvailability(isEntitled: { true }, hasAccount: { [unowned self] in self.hasAccount }),
            makeStore: { [unowned self] in self.store },
            now: { [unowned self] in Date(timeIntervalSince1970: self.time) },
            device: { [name] in name }
        )
    }

    private let name: String
    private let server: PretendServer

    init(_ name: String, server: PretendServer, values: [String: String] = [:], time: TimeInterval = 1000) {
        self.name = name
        self.values = values
        self.time = time
        self.server = server
        store = PretendCloudStore(server: server)
    }

    /// The app after a restart: the journal is kept, the mirror or the system engine's state only if asked.
    func relaunch(keepingMirror: Bool, keepingState: Bool) {
        store = store.relaunched(keepingMirror: keepingMirror, keepingState: keepingState)
        engine = makeEngine()
    }

    func edit(_ key: String, _ value: String?, at time: TimeInterval) {
        self.time = time
        values[key] = value
        engine.localChanged()
    }
}

/// The engine over the CloudKit store's logic, with a pretend server. What real CloudKit does is not tested here.
struct CloudSyncEngineTests {
    private let server = PretendServer()

    private func mac(_ name: String, values: [String: String] = [:], time: TimeInterval = 1000) -> CloudMac {
        CloudMac(name, server: server, values: values, time: time)
    }

    @Test func anEditOnOneMacArrivesOnTheOther() {
        let a = mac("a")
        let b = mac("b")
        a.engine.setOn(true)
        b.engine.setOn(true)
        a.edit("alias", "\"saf\"", at: 2000)
        a.edit("s.aliases/app:/Applications/Café.app", "\"cafe\"", at: 2100)
        server.deliver()
        #expect(b.values == ["alias": "\"saf\"", "s.aliases/app:/Applications/Café.app": "\"cafe\""])
        #expect(server.names.count == 2)
        #expect(server.names.contains("alias"))
        #expect(a.store.core.mirror.pending.isEmpty)
    }

    @Test func twoMacsThatChangedTheSameValueOfflineEndWithTheNewerOne() {
        for newerSendsFirst in [true, false] {
            let server = PretendServer()
            let a = CloudMac("a", server: server, values: ["alias": "\"one\""])
            let b = CloudMac("b", server: server, values: ["alias": "\"one\""])
            a.engine.setOn(true)
            b.engine.setOn(true)
            server.deliver()
            a.store.isOnline = false
            b.store.isOnline = false
            a.edit("alias", "\"older\"", at: 2000)
            b.edit("alias", "\"newer\"", at: 3000)
            (newerSendsFirst ? b : a).store.isOnline = true
            server.deliver()
            a.store.isOnline = true
            b.store.isOnline = true
            server.deliver()
            #expect(a.values["alias"] == "\"newer\"")
            #expect(b.values["alias"] == "\"newer\"")
            #expect(a.store.core.mirror.pending.isEmpty)
            #expect(b.store.core.mirror.pending.isEmpty)
        }
    }

    @Test func aMacThatJoinsLaterMergesWithWhatICloudHolds() {
        let a = mac("a", values: ["alias/a": "\"a\"", "layout": "\"compact\""], time: 100)
        a.engine.setOn(true)
        server.deliver()
        let b = mac("b", values: ["alias/b": "\"b\"", "layout": "\"extended\""], time: 300)
        b.engine.setOn(true)
        server.deliver()
        let merged = ["alias/a": "\"a\"", "alias/b": "\"b\"", "layout": "\"extended\""]
        #expect(a.values == merged)
        #expect(b.values == merged)
    }

    @Test func removingFromICloudDeletesTheZoneAndSwitchesEveryMacOff() {
        let a = mac("a", values: ["alias": "\"a\""])
        let b = mac("b", values: ["other": "\"b\""])
        a.engine.setOn(true)
        b.engine.setOn(true)
        server.deliver()
        #expect(server.names == ["alias", "other"])
        a.time = 5000
        a.engine.removeFromCloud()
        server.deliver()
        #expect(server.names == [SyncEngine.clearedKey], "only the note is left, in a zone made anew")
        #expect(a.timesTurnedOff == 1)
        #expect(b.timesTurnedOff == 1)
        #expect(!b.engine.isOn)
        #expect(a.values == ["alias": "\"a\"", "other": "\"b\""], "each Mac keeps its settings")
        #expect(b.values == ["alias": "\"a\"", "other": "\"b\""])
        b.time = 6000
        b.engine.setOn(true)
        server.deliver()
        #expect(b.engine.isOn, "a note read on joining is not meant for this Mac")
        #expect(server.names.count == 3)
    }

    @Test func dataPurgedInICloudsSettingsSwitchesSyncOffAndStaysGone() {
        let a = mac("a", values: ["alias": "\"a\""])
        a.engine.setOn(true)
        server.deliver()
        server.purge()
        server.deliver()
        #expect(!a.engine.isOn)
        #expect(a.timesTurnedOff == 1)
        #expect(server.names.isEmpty)
        #expect(a.values == ["alias": "\"a\""])
    }

    @Test func anotherAccountGetsWhatThisMacHasAndTheSettingsStay() {
        let a = mac("a", values: ["alias": "\"a\""])
        a.engine.setOn(true)
        a.store.account(.signedIn("first"))
        server.deliver()
        server.purge()
        a.store.purged = false
        a.store.isOnline = false
        a.store.account(.switchedAccount("second"))
        #expect(a.store.core.mirror.server.isEmpty)
        #expect(a.store.core.mirror.pending.keys.sorted() == ["alias"], "the engine found the store empty and sent what it has")
        a.store.isOnline = true
        server.deliver()
        #expect(a.values == ["alias": "\"a\""])
        #expect(server.names == ["alias"], "uploaded to the new account as a first sync does")
        #expect(a.store.core.mirror.account == "second")
        #expect(a.engine.isOn)
    }

    @Test func signingOutStopsTheExchangeAndKeepsTheSettings() {
        let a = mac("a", values: ["alias": "\"a\""])
        a.engine.setOn(true)
        server.deliver()
        a.hasAccount = false
        a.store.account(.signedOut)
        #expect(a.engine.status.state == .noAccount)
        #expect(a.store.core.mirror == SyncMirror())
        #expect(a.values == ["alias": "\"a\""])
    }

    @Test func anAccountWithoutRoomShowsAsFullUntilThereIsRoom() {
        let a = mac("a")
        a.engine.setOn(true)
        server.deliver()
        server.hasRoom = false
        a.edit("alias", "\"saf\"", at: 2000)
        server.deliver()
        #expect(a.engine.status.state == .full)
        #expect(server.names.isEmpty)
        a.edit("other", "1", at: 2500)
        server.hasRoom = true
        server.deliver()
        #expect(a.engine.status.state == .synced(Date(timeIntervalSince1970: 2500)))
        #expect(server.names == ["alias", "other"])
    }

    @Test func losingTheMirrorOrTheSavedStateIsMadeGoodByTheNextFetch() {
        for (keepingMirror, keepingState) in [(false, true), (true, false), (false, false), (true, true)] {
            let server = PretendServer()
            let a = CloudMac("a", server: server, values: ["alias": "\"a\"", "old": "1"])
            let b = CloudMac("b", server: server)
            a.engine.setOn(true)
            b.engine.setOn(true)
            server.deliver()
            a.store.isOnline = false
            a.edit("mine", "\"kept\"", at: 1500)
            b.edit("alias", "\"b\"", at: 2000)
            b.edit("old", nil, at: 2100)
            server.deliver()
            a.time = 3000
            a.relaunch(keepingMirror: keepingMirror, keepingState: keepingState)
            a.engine.setOn(true)
            server.deliver()
            let expected = ["alias": "\"b\"", "mine": "\"kept\""]
            #expect(a.values == expected)
            #expect(b.values == expected)
            #expect(a.store.core.mirror.server.keys.sorted() == ["alias", "mine", "old"], "the removal is a record too")
            #expect(a.store.core.mirror.pending.isEmpty)
        }
    }
}
