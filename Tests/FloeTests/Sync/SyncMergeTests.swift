//
//  SyncMergeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SyncMergeTests {
    private func value(_ text: String, at time: TimeInterval, on device: String) -> SyncRecord {
        SyncRecord(value: "\"\(text)\"", time: time, device: device)
    }

    private func removal(at time: TimeInterval, on device: String) -> SyncRecord {
        SyncRecord(value: nil, time: time, device: device)
    }

    /// What each side holds once both have merged the other's records.
    private func settled(_ left: [String: SyncRecord], _ right: [String: SyncRecord]) -> ([String: SyncRecord], [String: SyncRecord]) {
        (SyncMerge.merge(local: left, remote: right).merged, SyncMerge.merge(local: right, remote: left).merged)
    }

    @Test func theNewerChangeWinsWhicheverSideMerges() {
        let old = ["alias": value("saf", at: 10, on: "a")]
        let new = ["alias": value("safari", at: 20, on: "b")]
        let (left, right) = settled(old, new)
        #expect(left == new)
        #expect(right == new)
        #expect(SyncMerge.merge(local: old, remote: new).apply == ["alias"])
        #expect(SyncMerge.merge(local: new, remote: old).push == ["alias"])
        #expect(SyncMerge.merge(local: new, remote: old).apply.isEmpty, "an older record from the store is never taken in")
    }

    @Test func aTieGoesToTheSameDeviceOnBothSides() {
        let one = ["layout": value("compact", at: 10, on: "a")]
        let other = ["layout": value("extended", at: 10, on: "b")]
        let (left, right) = settled(one, other)
        #expect(left == other)
        #expect(right == other)
    }

    @Test func theSameStampOnDifferentRecordsStillSettlesOneWay() {
        let kept = ["alias": value("x", at: 10, on: "a")]
        let gone = ["alias": removal(at: 10, on: "a")]
        let (left, right) = settled(kept, gone)
        #expect(left == gone)
        #expect(right == gone)
        let (first, second) = settled(["alias": value("x", at: 10, on: "a")], ["alias": value("y", at: 10, on: "a")])
        #expect(first == second)
    }

    @Test func aLaterEditBeatsARemoval() {
        let removed = ["snippet": removal(at: 10, on: "a")]
        let edited = ["snippet": value("hello", at: 20, on: "b")]
        let (left, right) = settled(removed, edited)
        #expect(left == edited)
        #expect(right == edited)
    }

    @Test func aLaterRemovalBeatsAnEdit() {
        let edited = ["snippet": value("hello", at: 10, on: "b")]
        let removed = ["snippet": removal(at: 20, on: "a")]
        let (left, right) = settled(edited, removed)
        #expect(left == removed)
        #expect(right == removed)
        #expect(SyncMerge.merge(local: edited, remote: removed).apply == ["snippet"])
    }

    @Test func aKeyOnlyOneSideHoldsIsKeptAndSent() {
        let mine = ["alias/a": value("a", at: 10, on: "a")]
        let theirs = ["alias/b": value("b", at: 5, on: "b")]
        let outcome = SyncMerge.merge(local: mine, remote: theirs)
        #expect(outcome.merged.keys.sorted() == ["alias/a", "alias/b"], "absence on one side removes nothing")
        #expect(outcome.push == ["alias/a"])
        #expect(outcome.apply == ["alias/b"])
    }

    @Test func theSameChangeTwiceChangesNothingTheSecondTime() {
        let mine = ["alias": value("a", at: 10, on: "a")]
        let theirs = ["alias": value("b", at: 20, on: "b")]
        let once = SyncMerge.merge(local: mine, remote: theirs)
        let twice = SyncMerge.merge(local: once.merged, remote: theirs)
        #expect(twice.merged == once.merged)
        #expect(twice.apply.isEmpty)
        #expect(twice.push.isEmpty)
    }

    @Test func threeDevicesAgreeInAnyOrder() {
        let a = ["k": value("a", at: 10, on: "a"), "only-a": value("1", at: 1, on: "a")]
        let b = ["k": value("b", at: 30, on: "b"), "gone": removal(at: 40, on: "b")]
        let c = ["k": value("c", at: 20, on: "c"), "gone": value("still", at: 35, on: "c")]
        let orders = [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]]
        let results = orders.map { order in
            order.dropFirst().reduce(order[0]) { SyncMerge.merge(local: $0, remote: $1).merged }
        }
        let first = results[0]
        for result in results {
            #expect(result == first)
        }
        #expect(first["k"] == b["k"])
        #expect(first["gone"] == b["gone"])
        #expect(first["only-a"] == a["only-a"])
    }

    @Test func bothSidesHoldingDifferentDataBecomeTheSameData() {
        let left = ["a": value("1", at: 5, on: "a"), "b": value("2", at: 50, on: "a"), "c": value("3", at: 7, on: "a")]
        let right = ["b": value("two", at: 40, on: "b"), "c": value("three", at: 70, on: "b"), "d": value("4", at: 1, on: "b")]
        let (one, other) = settled(left, right)
        #expect(one == other)
        #expect(one["a"] == left["a"])
        #expect(one["b"] == left["b"])
        #expect(one["c"] == right["c"])
        #expect(one["d"] == right["d"])
    }

    @Test func removalsAreForgottenAfterNinetyDays() {
        let now = Date(timeIntervalSince1970: 100 * 86400)
        let records = [
            "old": removal(at: 9 * 86400, on: "a"),
            "recent": removal(at: 11 * 86400, on: "a"),
            "value": value("kept", at: 0, on: "a"),
        ]
        #expect(SyncMerge.expiredRemovals(in: records, now: now) == ["old"])
    }
}
