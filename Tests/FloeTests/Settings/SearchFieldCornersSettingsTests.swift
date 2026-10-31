//
//  SearchFieldCornersSettingsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing
import ThawUI

/// The slider's setting beside the old `searchFieldShape`, which earlier versions wrote and older Floes still read.
struct SearchFieldCornersSettingsTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-corners-\(UUID().uuidString)")
    private let cloud = MemorySyncCloud()

    private func floe(_ name: String) throws -> SyncedFloe {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SyncedFloe(cloud: cloud, folder: folder, name: name)
    }

    /// Settings as an earlier version saved them: the same blob with only the old key.
    private func defaultsFromAnEarlierVersion(shape: String?) throws -> MemoryDefaults {
        let defaults = MemoryDefaults()
        AppSettings(defaults: defaults, savesAfterEdits: false).save()
        let data = try #require(defaults.data(forKey: "settings"))
        var stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        stored["searchFieldCorners"] = nil
        stored["searchFieldShape"] = shape
        try defaults.set(JSONSerialization.data(withJSONObject: stored), forKey: "settings")
        return defaults
    }

    private func storedObject(_ settings: AppSettings) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: settings.exportedJSON()) as? [String: Any])
    }

    /// What an older Floe reads: the old field, by the old type, and nothing else about corners.
    private func whatAnOlderFloeReads(_ records: [String: String]) throws -> SearchFieldShape {
        let text = try #require(records["s.searchFieldShape"])
        return try JSONDecoder().decode(SearchFieldShape.self, from: Data(text.utf8))
    }

    // MARK: Migration

    @Test(arguments: [
        ("square", 0.0), ("rounded", 0.5), ("capsule", 1.0),
    ] as [(String, Double)])
    func settingsFromBeforeTheSliderTakeTheirPlaceOnIt(shape: String, roundness: Double) throws {
        let defaults = try defaultsFromAnEarlierVersion(shape: shape)
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.searchFieldCorners.roundness == roundness)
        settings.save()
        let stored = try storedObject(settings)
        #expect(stored["searchFieldShape"] as? String == shape, "the old key stays for an older Floe")
        #expect(stored["searchFieldCorners"] as? Double == roundness)
    }

    /// The radii each shape drew before the slider, at the launcher's own heights, in both layouts.
    @Test(arguments: [
        ("square", 0, 0, 0, RoundedCornerStyle.continuous),
        ("rounded", 12, 24, 24, .continuous),
        ("capsule", 22, 33.5, 24, .circular),
    ] as [(String, CGFloat, CGFloat, CGFloat, RoundedCornerStyle)])
    func nobodysLauncherChangesOnUpdate(shape: String, inPanel: CGFloat, fieldPiece: CGFloat, resultsPiece: CGFloat, style: RoundedCornerStyle) throws {
        let settings = try AppSettings(defaults: defaultsFromAnEarlierVersion(shape: shape), savesAfterEdits: false)
        let corners = settings.searchFieldCorners
        #expect(corners.cornerRadius(height: 44) == inPanel)

        let look = LauncherLook(glass: LauncherGlass(style: .dynamic), tint: LauncherTint(), border: LauncherBorder(), hasShadow: true)
        let heights = LauncherPanelState().pieceHeights(in: .extended)
        #expect(heights.field == 67)
        let pieces = PanelPieces(look: look, corners: corners, heights: heights)
        let field = pieces.fieldAppearance(facesResults: true)
        #expect(field.cornerRadius == fieldPiece)
        #expect(field.cornerStyle == style)
        #expect(pieces.fieldOutline().cornerSize.width == fieldPiece)
        #expect(pieces.fieldOutline().style == style)
        #expect(pieces.resultsAppearance().cornerRadius == resultsPiece)
        #expect(pieces.resultsAppearance().cornerStyle == .continuous)
        #expect(pieces.wholeAppearance().cornerRadius == resultsPiece)
    }

    @Test func settingsWithNeitherKeyAreRounded() throws {
        let settings = try AppSettings(defaults: defaultsFromAnEarlierVersion(shape: nil), savesAfterEdits: false)
        #expect(settings.searchFieldCorners == .rounded)
    }

    @Test func aRoundnessThatCannotBeReadFallsBackToTheShape() throws {
        let defaults = try defaultsFromAnEarlierVersion(shape: "capsule")
        let data = try #require(defaults.data(forKey: "settings"))
        var stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        stored["searchFieldCorners"] = "very round"
        try defaults.set(JSONSerialization.data(withJSONObject: stored), forKey: "settings")
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).searchFieldCorners == .capsule)
    }

    @Test func aRoundnessIsKeptExactlyAndStoredWithItsNearestShape() throws {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        settings.searchFieldCorners.roundness = 0.85
        settings.save()
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).searchFieldCorners.roundness == 0.85)
        let stored = try storedObject(settings)
        #expect(stored["searchFieldCorners"] as? Double == 0.85)
        #expect(stored["searchFieldShape"] as? String == "capsule")
    }

    @Test func anImportedFileFromBeforeTheSliderTakesItsPlaceToo() throws {
        let settings = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        settings.searchFieldCorners.roundness = 0.3
        settings.save()
        let older = try defaultsFromAnEarlierVersion(shape: "square")
        try settings.importJSON(#require(older.data(forKey: "settings")))
        #expect(settings.searchFieldCorners == .square)
    }

    // MARK: Sync as records

    private func applying(_ changed: [String: String], to settings: [String: Any]) -> (settings: [String: Any], refused: Set<String>) {
        SettingsSync.applying(changed, removed: [], to: settings)
    }

    @Test func bothFieldsSync() {
        let names = SettingsSync.synced.map(\.name)
        #expect(names.contains("searchFieldShape"))
        #expect(names.contains("searchFieldCorners"))
    }

    @Test(arguments: [(0.1, "square"), (0.3, "rounded"), (0.5, "rounded"), (0.8, "capsule")] as [(Double, String)])
    func recordsCarryTheRoundnessAndTheNearestShape(roundness: Double, shape: String) throws {
        let settings = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        settings.searchFieldCorners.roundness = roundness
        let records = try SettingsSync.records(of: storedObject(settings))
        #expect(records["s.searchFieldCorners"].flatMap(Double.init) == roundness)
        #expect(records["s.searchFieldShape"] == "\"\(shape)\"")
    }

    @Test(arguments: [("square", 0.0), ("capsule", 1.0)] as [(String, Double)])
    func anOlderMacsShapeMovesTheSlider(shape: String, roundness: Double) {
        let result = applying(["s.searchFieldShape": "\"\(shape)\""], to: ["searchFieldShape": "rounded", "searchFieldCorners": 0.3])
        #expect(result.settings["searchFieldShape"] as? String == shape)
        #expect(result.settings["searchFieldCorners"] as? Double == roundness)
    }

    @Test func anOlderMacsShapeThatIsAlreadyTheNearestLeavesTheSliderWhereItIs() {
        let result = applying(["s.searchFieldShape": "\"rounded\""], to: ["searchFieldShape": "rounded", "searchFieldCorners": 0.3])
        #expect(result.settings["searchFieldCorners"] as? Double == 0.3)
    }

    @Test func aShapeArrivingBeforeAnyRoundnessWasStoredSetsOne() {
        let result = applying(["s.searchFieldShape": "\"capsule\""], to: ["searchFieldShape": "rounded"])
        #expect(result.settings["searchFieldCorners"] as? Double == 1)
    }

    @Test func aNewerMacsTwoRecordsKeepItsExactRoundness() {
        let result = applying(["s.searchFieldShape": "\"capsule\"", "s.searchFieldCorners": "0.85"], to: ["searchFieldShape": "rounded", "searchFieldCorners": 0.3])
        #expect(result.settings["searchFieldCorners"] as? Double == 0.85)
        #expect(result.settings["searchFieldShape"] as? String == "capsule")
        #expect(result.refused.isEmpty)
    }

    @Test func aRoundnessArrivingAloneBringsTheShapeIntoStep() {
        let result = applying(["s.searchFieldCorners": "0.85"], to: ["searchFieldShape": "rounded", "searchFieldCorners": 0.3])
        #expect(result.settings["searchFieldCorners"] as? Double == 0.85)
        #expect(result.settings["searchFieldShape"] as? String == "capsule")
    }

    @Test func theTwoRecordsArrivingOneAfterTheOtherAgreeEitherWay() {
        let before: [String: Any] = ["searchFieldShape": "rounded", "searchFieldCorners": 0.3]
        let shape = ["s.searchFieldShape": "\"capsule\""]
        let corners = ["s.searchFieldCorners": "0.85"]
        let shapeFirst = applying(corners, to: applying(shape, to: before).settings).settings
        let cornersFirst = applying(shape, to: applying(corners, to: before).settings).settings
        #expect(shapeFirst["searchFieldCorners"] as? Double == 0.85)
        #expect(cornersFirst["searchFieldCorners"] as? Double == 0.85)
        #expect(shapeFirst["searchFieldShape"] as? String == "capsule")
        #expect(cornersFirst["searchFieldShape"] as? String == "capsule")
    }

    @Test func aShapeTheTwoRecordsDisagreeWithWinsSinceOnlyAnOlderMacWritesThat() {
        let result = applying(["s.searchFieldShape": "\"capsule\"", "s.searchFieldCorners": "0.3"], to: ["searchFieldShape": "rounded", "searchFieldCorners": 0.3])
        #expect(result.settings["searchFieldCorners"] as? Double == 1)
    }

    @Test func recordsThatCannotBeReadAreRefusedAndChangeNothing() {
        let before: [String: Any] = ["searchFieldShape": "rounded", "searchFieldCorners": 0.3]
        let result = applying(["s.searchFieldShape": "\"oval\"", "s.searchFieldCorners": "\"round\""], to: before)
        #expect(result.refused == ["s.searchFieldShape", "s.searchFieldCorners"])
        #expect(result.settings["searchFieldShape"] as? String == "rounded")
        #expect(result.settings["searchFieldCorners"] as? Double == 0.3)
    }

    // MARK: Sync between Macs

    private func snapshot(_ mac: SyncedFloe) -> [String: String] {
        SettingsSyncService.snapshot(settings: mac.settings, snippets: mac.snippets, quicklinks: mac.quicklinks)
    }

    @Test func aFineValueTravelsWholeAndAnOlderFloeWouldReadItsNearestShape() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        a.settings.searchFieldCorners.roundness = 0.35
        a.changed(at: 2000)
        cloud.deliver()
        #expect(b.settings.searchFieldCorners.roundness == 0.35)
        #expect(try whatAnOlderFloeReads(snapshot(b)) == .rounded)
        a.settings.searchFieldCorners.roundness = 0.9
        a.changed(at: 3000)
        cloud.deliver()
        #expect(b.settings.searchFieldCorners.roundness == 0.9)
        #expect(try whatAnOlderFloeReads(snapshot(b)) == .capsule)
    }

    @Test func whatAnOlderMacWritesMovesEveryNewerMacAndStaysPut() throws {
        let a = try floe("a")
        let b = try floe("b")
        a.settings.searchFieldCorners.roundness = 0.35
        a.settings.save()
        a.service.engine.setOn(true)
        b.service.engine.setOn(true)
        cloud.deliver()
        #expect(b.settings.searchFieldCorners.roundness == 0.35)

        // An older Floe changes the one record it knows, and leaves the rest.
        a.store.plant(SyncWire.encode(SyncRecord(value: "\"capsule\"", time: 5000, device: "older"), key: "s.searchFieldShape"), for: "s.searchFieldShape")
        a.service.engine.refresh()
        b.store.plant(SyncWire.encode(SyncRecord(value: "\"capsule\"", time: 5000, device: "older"), key: "s.searchFieldShape"), for: "s.searchFieldShape")
        b.service.engine.refresh()
        #expect(a.settings.searchFieldCorners == .capsule)
        #expect(b.settings.searchFieldCorners == .capsule)

        // The slider's new place goes up, and neither Mac is moved again by it.
        a.changed(at: 6000)
        b.changed(at: 6000)
        cloud.deliver()
        #expect(a.settings.searchFieldCorners == .capsule)
        #expect(b.settings.searchFieldCorners == .capsule)
        #expect(try whatAnOlderFloeReads(snapshot(a)) == .capsule)
        #expect(a.store.refusedKeys.isEmpty)
    }

    @Test func aMacThatHasNotChangedTheSliderUploadsNothingForIt() throws {
        let mac = try floe("a")
        #expect(snapshot(mac)["s.searchFieldCorners"] == SettingsSyncService.freshRecords()["s.searchFieldCorners"])
        #expect(snapshot(mac)["s.searchFieldShape"] == SettingsSyncService.freshRecords()["s.searchFieldShape"])
    }

    // MARK: Search

    @Test func theSettingsSearchFindsTheSliderByItsNewAndItsOldWords() throws {
        let entry = try #require(SearchIndex.appearanceEntries.first { $0.id == "appearance.searchFieldCorners" })
        #expect(entry.title == "Search field corners")
        #expect(entry.section == "Layout")
        for word in ["corners", "shape", "rounded", "capsule", "square"] {
            #expect(entry.keywords.contains(word), "\(word)")
        }
    }
}
