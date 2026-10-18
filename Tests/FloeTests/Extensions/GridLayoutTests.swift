//
//  GridLayoutTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct GridLayoutTests {
    /// Two sections: five items in the grid's three columns, then three in two wide columns of their own.
    ///
    ///     0 1 2      5 6
    ///     3 4        7
    private func layout() -> GridLayout {
        let root = Fixture.root(Fixture.node("Grid", props: ["columns": 3], children: [
            Fixture.node("Grid.Section", id: 10, props: ["title": "Recent"], children: (1 ... 5).map { Fixture.item("A\($0)", id: $0) }),
            Fixture.node("Grid.Section", id: 20, props: ["title": "Wallpapers", "subtitle": "3", "columns": 2, "aspectRatio": "16/9", "fit": "fill", "inset": "medium"], children: (6 ... 8).map { Fixture.item("B\($0)", id: $0) }),
        ]))
        let view = ViewState.view(in: root)!
        return GridLayout(view: view, rows: ViewState.rows(of: view, searchText: ""))
    }

    @Test func eachSectionTakesItsOwnShapeOrTheGrids() {
        let sections = layout().sections
        #expect(sections.map(\.items) == [0 ..< 5, 5 ..< 8])
        #expect(sections.map(\.columns) == [3, 2])
        #expect(sections.map(\.title) == ["Recent", "Wallpapers"])
        #expect(sections.map(\.subtitle) == [nil, "3"])
        #expect(sections.map(\.aspectRatio) == [1, 16.0 / 9])
        #expect(sections.map(\.fills) == [false, true])
        #expect(sections.map(\.inset) == [0, 0.12])
    }

    @Test func upAndDownKeepTheColumnAndCrossIntoTheNextSection() {
        let grid = layout()
        #expect(grid.moved(from: 1, lines: 1) == 4)
        #expect(grid.moved(from: 2, lines: 1) == 4, "a shorter line lands on its last item")
        #expect(grid.moved(from: 4, lines: 1) == 6)
        #expect(grid.moved(from: 3, lines: 1) == 5)
        #expect(grid.moved(from: 7, lines: 1) == 7, "past the last line the selection stays")
        #expect(grid.moved(from: 6, lines: -1) == 4)
        #expect(grid.moved(from: 5, lines: -1) == 3)
        #expect(grid.moved(from: 0, lines: -1) == 0)
        #expect(grid.moved(from: 0, lines: 9) == 7, "Page Down goes as far as there are lines")
        #expect(grid.moved(from: 99, lines: 1) == 99, "an index outside the grid is left alone")
    }

    @Test func leftAndRightStepAcrossLinesAndSections() {
        let grid = layout()
        #expect(grid.moved(from: 4, across: 1) == 5)
        #expect(grid.moved(from: 5, across: -1) == 4)
        #expect(grid.moved(from: 0, across: -1) == 0)
        #expect(grid.moved(from: 7, across: 1) == 7)
    }

    @Test func itemsOutsideASectionAreOneUntitledSectionInRaycastsDefaults() {
        let root = Fixture.root(Fixture.node("Grid", children: [Fixture.item("One", id: 1), Fixture.item("Two", id: 2)]))
        let view = ViewState.view(in: root)!
        let sections = GridLayout(view: view, rows: ViewState.rows(of: view, searchText: "")).sections
        #expect(sections.count == 1)
        #expect(sections.first?.title == nil)
        #expect(sections.first?.columns == 5)
        #expect(sections.first?.aspectRatio == 1)
    }

    @Test func columnsAndShapesReadAsRaycastWritesThem() {
        #expect(GridLayout.columns(nil, itemSize: "small") == 8)
        #expect(GridLayout.columns(nil, itemSize: "large") == 3)
        #expect(GridLayout.columns(20, itemSize: nil) == 8)
        #expect(GridLayout.columns(0, itemSize: nil) == 1)
        #expect(GridLayout.aspectRatio("3/2") == 1.5)
        #expect(GridLayout.aspectRatio("2/3") == 2.0 / 3)
        #expect(GridLayout.aspectRatio("wide") == 1)
        #expect(GridLayout.inset("lg") == 0.2, "Raycast's Grid.Inset.Large")
        #expect(GridLayout.inset("large") == 0.2)
        #expect(GridLayout.inset("zero") == 0)
        #expect(GridLayout.inset(nil) == 0)
    }
}
