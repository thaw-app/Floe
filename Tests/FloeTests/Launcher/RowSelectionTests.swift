//
//  RowSelectionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct RowSelectionTests {
    @Test func aMoveTellsTheRowLeftAndTheRowReachedAndNoOther() {
        let rows = RowSelection()
        let flags = ["a", "b", "c"].map { rows.flag(for: $0) }
        rows.select("a")
        #expect(flags.map(\.isOn) == [true, false, false])

        var changed: [Int] = []
        let watching = flags.enumerated().map { index, flag in
            flag.objectWillChange.sink { changed.append(index) }
        }
        rows.select("b")

        #expect(flags.map(\.isOn) == [false, true, false])
        #expect(changed.sorted() == [0, 1], "the third row is not drawn again")
        withExtendedLifetime(watching) {}
    }

    @Test func aRowThatAppearsLaterAlreadyKnowsWhetherItIsSelected() {
        let rows = RowSelection()
        rows.select("far")
        #expect(rows.flag(for: "far").isOn)
        #expect(!rows.flag(for: "near").isOn)
    }

    @Test func selectingTheSameRowAgainTellsNobody() {
        let rows = RowSelection()
        let flag = rows.flag(for: "a")
        rows.select("a")
        var changes = 0
        let watching = flag.objectWillChange.sink { changes += 1 }
        rows.select("a")
        #expect(changes == 0)
        withExtendedLifetime(watching) {}
    }

    @Test func newResultsStartOverAndKeepNoFlagOfARowThatIsGone() {
        let rows = RowSelection()
        let old = rows.flag(for: "a")
        rows.select("a")
        rows.reset()
        #expect(rows.selected == nil)
        #expect(rows.flag(for: "a") !== old)
        #expect(!rows.flag(for: "a").isOn)
    }

    @Test func theModelsSelectionIsTheRowThatIsTold() throws {
        let scratch = MemoryDefaults()
        let model = LauncherModel(settings: AppSettings(defaults: scratch), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.query = ""
        try #require(model.results.count >= 2, "the built-in rows are enough for this")
        let first = model.results[0].id
        let second = model.results[1].id
        #expect(model.rowSelection.selected == first)

        model.selection = 1
        #expect(model.rowSelection.selected == second)
        #expect(model.rowSelection.flag(for: second).isOn)
        #expect(!model.rowSelection.flag(for: first).isOn)

        let version = model.resultsVersion
        model.query = "zzzz no such thing"
        #expect(model.resultsVersion > version, "new results are a new list to draw")
    }

    @Test func whileTypingIsPacedTheRowsKeepTheTextTheirResultsAnswer() {
        let scratch = MemoryDefaults()
        let model = LauncherModel(settings: AppSettings(defaults: scratch), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.typing.window = 60

        model.query = "s"
        let version = model.resultsVersion
        #expect(model.searchedQuery == "s", "the first key is answered at once")

        model.query = "se"
        #expect(model.searchedQuery == "s", "the list on screen still answers the first key")
        #expect(model.resultsVersion == version, "and is not drawn again with the new text")

        model.typing.flush()
        #expect(model.searchedQuery == "se")
        #expect(model.resultsVersion > version)
    }
}
