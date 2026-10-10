//
//  CloudSyncCoreTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The CloudKit store's decisions, driven by made-up events. No CloudKit call is made here or anywhere in the tests.
struct CloudSyncCoreTests {
    private func entry(_ json: String, tag: String = "1") -> CloudSyncEntry {
        CloudSyncEntry(json: json, system: Data(tag.utf8))
    }

    /// A store that has fetched and knows its zone, holding these records.
    private func settled(_ server: [String: CloudSyncEntry] = [:]) -> CloudSyncCore {
        let mirror = SyncMirror(server: server, account: "user", zoneExists: true, hasFetched: true)
        return CloudSyncCore(mirror: mirror, hasSavedState: true)
    }

    private func sent(
        saved: [String: CloudSyncEntry] = [:],
        deleted: [String] = [],
        failedSaves: [String: CloudSyncFailure] = [:],
        failedDeletes: [String: CloudSyncFailure] = [:]
    ) -> CloudSyncEvent {
        .sent(saved: saved, deleted: deleted, failedSaves: failedSaves, failedDeletes: failedDeletes)
    }

    @Test func nothingIsSentBeforeTheFirstFetchEnds() {
        var core = CloudSyncCore(mirror: nil, hasSavedState: false)
        #expect(core.set("{\"t\":1}", for: "alias").isEmpty)
        #expect(core.contents["alias"] as? [String: Int] == ["t": 1], "the store answers with it at once all the same")
        #expect(core.outgoing("alias") == nil)
        #expect(core.resend().isEmpty)
        let effects = core.handle(.fetchFinished)
        #expect(effects.commands == [.saveZone, .save("alias")])
        #expect(effects.change == .initialValues)
        #expect(core.outgoing("alias") == CloudSyncEntry(json: "{\"t\":1}", system: nil))
    }

    @Test func fetchedChangesAreReportedOnceWhenTheFetchEnds() {
        var core = settled(["old": entry("1")])
        let first = core.handle(.fetched(changed: ["alias": entry("2")], deleted: []))
        let second = core.handle(.fetched(changed: [:], deleted: ["old"]))
        #expect(first.change == nil)
        #expect(second.change == nil)
        #expect(core.handle(.fetchFinished).change == .values)
        #expect(core.contents.keys.sorted() == ["alias"])
        #expect(core.handle(.fetchFinished).change == nil, "a fetch that brought nothing is not news")
    }

    @Test func aFetchThatChangesOnlyTheServersFieldsIsNotNews() {
        var core = settled(["alias": entry("1", tag: "1")])
        _ = core.handle(.fetched(changed: ["alias": entry("1", tag: "2")], deleted: []))
        #expect(core.handle(.fetchFinished).change == nil)
        #expect(core.mirror.server["alias"]?.system == Data("2".utf8))
    }

    @Test func aFetchedRecordReplacesAChangeThatWaited() {
        var core = settled(["alias": entry("1")])
        #expect(core.set("2", for: "alias") == [.save("alias")])
        let effects = core.handle(.fetched(changed: ["alias": entry("3", tag: "9")], deleted: []))
        #expect(effects.commands == [.forget("alias")])
        #expect(core.mirror.pending.isEmpty)
        #expect(core.contents["alias"] as? String == "3", "the engine sees the server's and sends its own again if that is newer")
        #expect(core.handle(.fetchFinished).change == .values)
    }

    @Test func aSavedRecordLeavesTheQueueAndKeepsTheServersFields() {
        var core = settled()
        #expect(core.set("1", for: "alias") == [.save("alias")])
        let effects = core.handle(sent(saved: ["alias": entry("1", tag: "7")]))
        #expect(effects == CloudSyncEffects())
        #expect(core.mirror.pending.isEmpty)
        #expect(core.set("2", for: "alias") == [.save("alias")])
        #expect(core.outgoing("alias") == entry("2", tag: "7"))
        #expect(core.set("2", for: "alias") == [.save("alias")], "set twice, queued twice, sent once")
    }

    @Test func settingWhatTheServerHoldsQueuesNothing() {
        var core = settled(["alias": entry("1")])
        #expect(core.set("1", for: "alias").isEmpty)
        #expect(core.mirror.pending.isEmpty)
    }

    @Test func aChangeMadeWhileItsSaveWasOnTheWayIsSentAgain() {
        var core = settled()
        _ = core.set("1", for: "alias")
        _ = core.set("2", for: "alias")
        let effects = core.handle(sent(saved: ["alias": entry("1", tag: "7")]))
        #expect(effects.commands == [.save("alias")])
        #expect(core.outgoing("alias") == entry("2", tag: "7"))
    }

    @Test func aRejectedSaveTakesTheServersRecordAndLetsTheEngineDecide() {
        var core = settled()
        _ = core.set("\"mine\"", for: "alias")
        let effects = core.handle(sent(failedSaves: ["alias": .conflict(entry("\"theirs\"", tag: "4"))]))
        #expect(effects.change == .values)
        #expect(effects.commands.isEmpty, "nothing is sent again until the engine says this Mac's value is the newer")
        #expect(core.mirror.pending.isEmpty)
        #expect(core.contents["alias"] as? String == "\"theirs\"")
        #expect(core.set("\"mine\"", for: "alias") == [.save("alias")])
        #expect(core.outgoing("alias") == entry("\"mine\"", tag: "4"), "the second save carries the server's fields and is taken")
    }

    @Test func aConflictWithoutTheServersRecordIsSentAfresh() {
        var core = settled(["alias": entry("1", tag: "1")])
        _ = core.set("2", for: "alias")
        #expect(core.handle(sent(failedSaves: ["alias": .conflict(nil)])).commands == [.save("alias")])
        #expect(core.outgoing("alias") == CloudSyncEntry(json: "2", system: nil))
        #expect(core.handle(sent(failedSaves: ["alias": .unknownItem])).commands == [.save("alias")])
    }

    @Test func aZoneThatWasNeverMadeIsMadeAndTheSaveRepeated() {
        var core = CloudSyncCore(mirror: SyncMirror(hasFetched: true), hasSavedState: true)
        #expect(core.set("1", for: "alias") == [.saveZone, .save("alias")])
        let effects = core.handle(sent(failedSaves: ["alias": .zoneMissing]))
        #expect(effects.commands == [.saveZone, .save("alias")])
        #expect(effects.change == nil)
        _ = core.handle(.zoneSaved)
        #expect(core.set("2", for: "alias") == [.save("alias")])
    }

    @Test func aZoneDeletedElsewhereIsReadAgainBeforeAnythingIsSent() {
        var core = settled(["alias": entry("1"), "other": entry("2")])
        _ = core.set("3", for: "alias")
        let effects = core.handle(.zoneLost(.deleted))
        #expect(effects.commands == [.forgetEverything, .fetch])
        #expect(effects.change == nil, "the engine is not told the store is empty, or it would put this Mac's copy back")
        #expect(core.contents.keys.sorted() == ["alias"], "what waited still waits")
        #expect(core.set("4", for: "new").isEmpty)
        _ = core.handle(.fetched(changed: ["~cleared": entry("{}")], deleted: []))
        let after = core.handle(.fetchFinished)
        #expect(after.change == .initialValues)
        #expect(after.commands == [.save("alias"), .save("new")])
        #expect(core.contents.keys.sorted() == ["alias", "new", "~cleared"])
    }

    @Test func aSaveIntoAZoneThatWentAwayCountsAsThatZoneDeleted() {
        var core = settled(["other": entry("2")])
        _ = core.set("3", for: "alias")
        let effects = core.handle(sent(failedSaves: ["alias": .zoneMissing]))
        #expect(effects.commands == [.forgetEverything, .fetch])
        #expect(core.mirror.server.isEmpty)
        #expect(!core.mirror.hasFetched)
        let reset = core.handle(.zoneLost(.keysReset))
        #expect(reset.commands == [.forgetEverything, .fetch])
        #expect(core.handle(.fetchFinished).commands == [.saveZone, .save("alias")])
    }

    @Test func dataTheUserPurgedIsNotPutBack() {
        var core = settled(["alias": entry("1")])
        _ = core.set("2", for: "other")
        for event in [CloudSyncEvent.zoneLost(.purged), sent(failedSaves: ["other": .zonePurged])] {
            var copy = core
            let effects = copy.handle(event)
            #expect(effects.change == .removed)
            #expect(effects.commands == [.forgetEverything])
            #expect(copy.contents.isEmpty)
            #expect(copy.resend().isEmpty)
            #expect(copy.mirror.account == "user")
        }
    }

    @Test func anAccountWithoutRoomHoldsTheChangeAndSaysSo() {
        var core = settled()
        _ = core.set("1", for: "alias")
        let effects = core.handle(sent(failedSaves: ["alias": .quotaExceeded]))
        #expect(effects.change == .overQuota)
        #expect(effects.commands.isEmpty, "not sent again at once, only at the next exchange")
        #expect(core.limits.isExhausted)
        #expect(!core.limits.fits([:]))
        #expect(core.resend() == [.save("alias")])
        let later = core.handle(sent(saved: ["alias": entry("1", tag: "2")]))
        #expect(later.change == .values, "so the engine sends what it held back")
        #expect(!core.limits.isExhausted)
        #expect(core.limits == .cloudKit)
        #expect(core.handle(.zoneSaveFailed(.quotaExceeded)).change == .overQuota)
        #expect(core.handle(.zoneSaveFailed(.later)).change == nil)
    }

    @Test func eachChangeOfAPartlyFailedRequestIsHandledByItsOwnResult() {
        var core = settled(["gone": entry("0", tag: "1")])
        for name in ["saved", "newer", "later", "refused", "skipped", "gone"] {
            _ = core.set("1", for: name)
        }
        let failures: [String: CloudSyncFailure] = [
            "newer": .conflict(entry("9", tag: "5")), "later": .later, "refused": .refused, "skipped": .batch, "gone": .unknownItem,
        ]
        let effects = core.handle(sent(saved: ["saved": entry("1", tag: "2")], failedSaves: failures))
        #expect(effects.change == .values)
        #expect(effects.commands == [.save("gone"), .save("skipped")])
        #expect(core.mirror.pending.keys.sorted() == ["gone", "later", "refused", "skipped"])
        #expect(core.outgoing("gone") == CloudSyncEntry(json: "1", system: nil), "its record is gone, so it is made anew")
        #expect(core.outgoing("refused") == nil)
        #expect(core.resend() == [.save("gone"), .save("later"), .save("skipped")], "a refused change waits for a new value")
        #expect(core.set("2", for: "refused") == [.save("refused")])
    }

    @Test func aRemovalIsQueuedAndForgottenOnceTheServerConfirms() {
        var core = settled(["alias": entry("1"), "other": entry("2")])
        #expect(core.remove("alias") == [.delete("alias")])
        #expect(core.remove("unknown").isEmpty)
        #expect(core.contents.keys.sorted() == ["other"])
        #expect(core.handle(sent(deleted: ["alias"])) == CloudSyncEffects())
        #expect(core.mirror.pending.isEmpty)
        #expect(core.mirror.server.keys.sorted() == ["other"])
        _ = core.remove("other")
        _ = core.handle(sent(failedDeletes: ["other": .unknownItem]))
        #expect(core.mirror.pending.isEmpty, "gone already is as good as deleted")
        #expect(core.mirror.server.isEmpty)
    }

    @Test func aRemovalThatFailedForNowIsTriedAtTheNextExchange() {
        var core = settled(["alias": entry("1")])
        _ = core.remove("alias")
        #expect(core.handle(sent(failedDeletes: ["alias": .later])).commands.isEmpty)
        #expect(core.resend() == [.delete("alias")])
        #expect(core.set("2", for: "alias") == [.save("alias")], "a value set after the removal replaces it")
    }

    @Test func removingEverythingDeletesTheZoneAndHoldsTheNoteUntilItIsGone() {
        var core = settled(["alias": entry("1")])
        _ = core.set("2", for: "other")
        #expect(core.removeAll() == [.forgetEverything, .deleteZone])
        #expect(core.contents.isEmpty)
        #expect(core.set("{}", for: "~cleared").isEmpty, "a save now would land in the zone that is being deleted")
        #expect(core.resend() == [.deleteZone], "asked again at the next exchange and after a restart")
        #expect(core.handle(.zoneDeletionFailed(.later)).commands.isEmpty)
        _ = core.handle(.fetched(changed: ["alias": entry("1")], deleted: []))
        #expect(core.handle(.fetchFinished).change == nil, "what is fetched from the zone being deleted is not taken in")
        #expect(core.mirror.server.isEmpty)
        #expect(core.mirror.isClearing)
        let effects = core.handle(.zoneDeletionSent)
        #expect(effects.commands == [.saveZone, .save("~cleared")])
        #expect(effects.change == nil)
        #expect(!core.mirror.isClearing)
    }

    @Test func aZoneThatWasAlreadyGoneCountsAsDeleted() {
        var core = settled()
        _ = core.removeAll()
        _ = core.set("{}", for: "~cleared")
        #expect(core.handle(.zoneDeletionFailed(.zoneMissing)).commands == [.saveZone, .save("~cleared")])
    }

    @Test func theFirstSignInKeepsWhatAlreadyWaits() {
        var core = CloudSyncCore(mirror: nil, hasSavedState: false)
        _ = core.set("1", for: "alias")
        let effects = core.handle(.signedIn("user"))
        #expect(effects == CloudSyncEffects(commands: [], change: .account))
        #expect(core.mirror.account == "user")
        #expect(core.mirror.pending.count == 1)
        #expect(core.handle(.signedIn("user")).commands.isEmpty)
    }

    @Test func signingOutClearsTheMirrorAndTheSavedState() {
        var core = settled(["alias": entry("1")])
        _ = core.set("2", for: "other")
        let effects = core.handle(.signedOut)
        #expect(effects == CloudSyncEffects(commands: [.restart], change: .account))
        #expect(core.mirror == SyncMirror())
        #expect(core.contents.isEmpty)
    }

    @Test func anotherAccountStartsFromAnEmptyMirror() {
        for event in [CloudSyncEvent.switchedAccount("other"), .signedIn("other")] {
            var core = settled(["alias": entry("1")])
            _ = core.set("2", for: "waiting")
            let effects = core.handle(event)
            #expect(effects == CloudSyncEffects(commands: [.restart], change: .account))
            #expect(core.mirror == SyncMirror(account: "other"))
            #expect(core.set("1", for: "alias").isEmpty, "held until the new account was read")
            #expect(core.handle(.fetchFinished).commands == [.saveZone, .save("alias")])
        }
    }

    @Test func aLostMirrorDropsTheSavedStateSoEverythingIsFetchedAgain() {
        let core = CloudSyncCore(mirror: nil, hasSavedState: true)
        #expect(!core.keepsSavedState)
        #expect(core.mirror == SyncMirror())
    }

    @Test func aLostStateForgetsWhatTheServerHeldButNotWhatWaits() {
        var mirror = SyncMirror(server: ["alias": entry("1")], account: "user", zoneExists: true, hasFetched: true)
        mirror.pending["other"] = SyncMirror.Change(json: "2")
        var core = CloudSyncCore(mirror: mirror, hasSavedState: false)
        #expect(!core.keepsSavedState)
        #expect(core.contents.keys.sorted() == ["other"])
        #expect(core.resend().isEmpty)
        _ = core.handle(.fetched(changed: ["alias": entry("1")], deleted: []))
        #expect(core.handle(.fetchFinished).commands == [.save("other")])
        #expect(core.contents.keys.sorted() == ["alias", "other"])
        #expect(CloudSyncCore(mirror: mirror, hasSavedState: true).keepsSavedState)
    }

    @Test func aRecordThatIsNotOneOfTheEnginesIsHandedOverAsText() {
        let core = settled(["fields": entry("{\"t\":5,\"d\":\"x\"}"), "text": entry("7"), "empty": CloudSyncEntry(json: nil, system: nil)])
        #expect(core.contents["fields"] is [String: Any])
        #expect(core.contents["text"] as? String == "7")
        #expect(core.contents["empty"] as? String == "")
        #expect(SyncWire.decode(core.contents, in: core.limits).skipped == 2)
    }

    @Test func theChangeTheEngineMustNotMissWins() {
        var effects = CloudSyncEffects()
        effects.note(.overQuota)
        effects.note(.values)
        #expect(effects.change == .overQuota)
        effects.note(.removed)
        #expect(effects.change == .removed)
    }

    @Test func theMirrorAndTheStateSurviveARestartAndCanBeLost() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-mirror-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = CloudSyncFiles.folder(folder)
        #expect(files.loadMirror() == nil)
        #expect(files.loadState() == nil)
        var mirror = SyncMirror(server: ["alias": entry("1")], refused: ["bad"], account: "user", zoneExists: true, hasFetched: true)
        mirror.pending = ["gone": SyncMirror.Change(json: nil), "new": SyncMirror.Change(json: "2")]
        files.saveMirror(mirror)
        files.saveState(Data("state".utf8))
        #expect(CloudSyncFiles.folder(folder).loadMirror() == mirror)
        #expect(CloudSyncFiles.folder(folder).loadState() == Data("state".utf8))
        files.saveState(nil)
        #expect(files.loadState() == nil)
        try Data("not a mirror".utf8).write(to: folder.appendingPathComponent("SyncMirror.json"))
        #expect(files.loadMirror() == nil)
    }
}
