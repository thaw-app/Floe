//
//  ViewStateTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ListStateTests {
    private func list(props: [String: Any] = [:], handlers: [String] = [], children: [[String: Any]]) -> Node {
        Fixture.root(Fixture.node("List", props: props, handlers: handlers, children: children))
    }

    @Test func findsTheViewOnTheTopScreen() {
        let root = Fixture.tree(Fixture.node("root", children: [
            Fixture.node("_screen", children: [Fixture.node("List", id: 1)]),
            Fixture.node("_screen", children: [Fixture.slot("unused", Fixture.node("X")), Fixture.node("Detail", id: 2)]),
        ]))
        #expect(ViewState.screen(in: root)?.children.count == 2)
        #expect(ViewState.view(in: root)?.id == 2, "the last screen is on top, and slots are not the view")
        #expect(ViewState.view(in: nil) == nil)
    }

    /// Since the renderer transmits only the visible screen, snapshots carry a single screen.
    @Test func findsTheViewOnASingleScreenSnapshot() {
        let root = Fixture.tree(Fixture.node("root", children: [
            Fixture.node("_screen", children: [Fixture.slot("unused", Fixture.node("X")), Fixture.node("Detail", id: 2)]),
        ]))
        #expect(ViewState.screen(in: root)?.children.count == 2)
        #expect(ViewState.view(in: root)?.id == 2)
        #expect(ViewState.isList(root) == false)
    }

    @Test(arguments: [("List", true), ("Grid", true), ("Detail", false), ("Form", false)])
    func listsAndGridsAreLists(type: String, expected: Bool) {
        #expect(ViewState.isList(Fixture.tree(Fixture.node(type))) == expected)
        #expect(ViewState.isList(nil) == false)
    }

    @Test func rowsFlattenSectionsAndKeepTheirTitles() {
        let root = list(children: [
            Fixture.item("Loose", id: 1),
            Fixture.node("List.Section", props: ["title": "Rocky"], children: [Fixture.item("Mercury", id: 2), Fixture.item("Venus", id: 3)]),
            Fixture.node("List.Section", children: [Fixture.item("Untitled", id: 4)]),
            Fixture.node("EmptyView"),
        ])
        let rows = ViewState.rows(of: ViewState.view(in: root), searchText: "")
        #expect(rows.map(\.id) == [1, 2, 3, 4])
        #expect(rows.map(\.sectionTitle) == [nil, "Rocky", "Rocky", nil])
    }

    @Test func rowsKeepTheirSectionsSubtitle() {
        let root = list(children: [
            Fixture.node("List.Section", props: ["title": "Rocky", "subtitle": "2 planets"], children: [Fixture.item("Mercury", id: 2)]),
            Fixture.node("List.Section", props: ["title": "Giants"], children: [Fixture.item("Jupiter", id: 5)]),
        ])
        let rows = ViewState.rows(of: ViewState.view(in: root), searchText: "")
        #expect(rows.map(\.sectionSubtitle) == ["2 planets", nil])
        #expect(rows[0] != Row(node: rows[0].node, sectionTitle: "Rocky", sectionID: rows[0].sectionID), "a changed subtitle draws the heading again")
    }

    @Test func eachSectionWithATitleOrASubtitleStartsWithAHeading() {
        let root = list(children: [
            Fixture.item("Loose", id: 1),
            Fixture.node("List.Section", id: 10, props: ["title": "Planets", "subtitle": "Rocky"], children: [Fixture.item("Mercury", id: 2), Fixture.item("Venus", id: 3)]),
            Fixture.node("List.Section", id: 11, props: ["title": "Planets", "subtitle": "Giants"], children: [Fixture.item("Jupiter", id: 4)]),
            Fixture.node("List.Section", id: 12, props: ["subtitle": "No title"], children: [Fixture.item("Pluto", id: 5)]),
            Fixture.node("List.Section", id: 13, children: [Fixture.item("Plain", id: 6)]),
        ])
        let rows = ViewState.rows(of: ViewState.view(in: root), searchText: "")
        let headings = rows.indices.map { ViewState.sectionHeading(at: $0, in: rows) }
        #expect(headings.map { $0?.title } == [nil, "Planets", nil, "Planets", "", nil], "the same title twice is two sections")
        #expect(headings.map { $0?.detail } == [nil, "Rocky", nil, "Giants", "No title", nil], "a subtitle shows without a title")
    }

    @Test func gridItemsAreRowsToo() {
        let root = Fixture.root(Fixture.node("Grid", children: [
            Fixture.node("Grid.Section", props: ["title": "Icons"], children: [Fixture.node("Grid.Item", id: 9, props: ["title": "Star"])]),
        ]))
        #expect(ViewState.rows(of: ViewState.view(in: root), searchText: "").map(\.id) == [9])
    }

    @Test func aViewThatIsNotAListHasNoRows() {
        #expect(ViewState.rows(of: Fixture.tree(Fixture.node("Detail")), searchText: "").isEmpty)
        #expect(ViewState.rows(of: nil, searchText: "").isEmpty)
    }

    @Test func filtersByEveryWordAcrossTitleSubtitleAndKeywords() {
        let root = list(children: [
            Fixture.item("Mercury", id: 1, subtitle: "0.39 AU", keywords: ["rocky", "inner"]),
            Fixture.item("Jupiter", id: 2, subtitle: "5.2 AU", keywords: ["gas"]),
            Fixture.item("Mars", id: 3, subtitle: "1.52 AU", keywords: ["rocky"]),
        ])
        let view = ViewState.view(in: root)
        #expect(ViewState.rows(of: view, searchText: "ROCKY").map(\.id) == [1, 3])
        #expect(ViewState.rows(of: view, searchText: "rocky m").map(\.id) == [1, 3])
        #expect(ViewState.rows(of: view, searchText: "rocky inner").map(\.id) == [1])
        #expect(ViewState.rows(of: view, searchText: "5.2").map(\.id) == [2])
        #expect(ViewState.rows(of: view, searchText: "pluto").isEmpty)
        #expect(ViewState.rows(of: view, searchText: "   ").count == 3, "blank text filters nothing")
    }

    @Test func aListThatHandlesSearchItselfIsNotFilteredHere() {
        let root = list(handlers: ["onSearchTextChange"], children: [Fixture.item("Mercury", id: 1), Fixture.item("Mars", id: 2)])
        #expect(ViewState.rows(of: ViewState.view(in: root), searchText: "mars").map(\.id) == [1, 2])
    }

    @Test func theFilteringPropOverridesTheDefault() {
        let children = [Fixture.item("Mercury", id: 1), Fixture.item("Mars", id: 2)]
        let on = list(props: ["filtering": true], handlers: ["onSearchTextChange"], children: children)
        let off = list(props: ["filtering": false], children: children)
        let options = list(props: ["filtering": ["keepSectionOrder": true]], handlers: ["onSearchTextChange"], children: children)
        #expect(ViewState.rows(of: ViewState.view(in: on), searchText: "mars").map(\.id) == [2])
        #expect(ViewState.rows(of: ViewState.view(in: off), searchText: "mars").map(\.id) == [1, 2])
        #expect(ViewState.rows(of: ViewState.view(in: options), searchText: "mars").map(\.id) == [2], "an options object means filtering is on")
    }

    @Test func selectionIsClampedToTheRows() {
        let rows = ViewState.rows(of: ViewState.view(in: list(children: [Fixture.item("A", id: 1), Fixture.item("B", id: 2)])), searchText: "")
        #expect(ViewState.selectedRow(rows, selection: 0)?.id == 1)
        #expect(ViewState.selectedRow(rows, selection: 9)?.id == 2)
        #expect(ViewState.selectedRow(rows, selection: -3)?.id == 1)
        #expect(ViewState.selectedRow([], selection: 0) == nil)
    }

    @Test(arguments: [(-5, 3, 0), (0, 3, 0), (2, 3, 2), (7, 3, 2), (Int.max / 2, 3, 2), (4, 0, 0)])
    func clampKeepsAnIndexInRange(index: Int, count: Int, expected: Int) {
        #expect(ViewState.clamp(index, count: count) == expected)
    }
}

struct ActionStateTests {
    private let panel = Fixture.node("ActionPanel", id: 100, children: [
        Fixture.action("Open", id: 1),
        Fixture.node("ActionPanel.Section", props: ["title": "Copy"], children: [Fixture.action("Copy Title", id: 2), Fixture.action("Copy Link", id: 3)]),
        Fixture.node("ActionPanel.Section", children: [Fixture.action("Untitled Section Action", id: 4)]),
        Fixture.node("ActionPanel.Submenu", id: 5, props: ["title": "Set Priority"], children: [Fixture.action("High", id: 6), Fixture.action("Low", id: 7)]),
    ])

    @Test func aRowsOwnPanelWinsOverTheListsPanel() {
        let item = Fixture.node("List.Item", id: 10, props: ["title": "Row"], children: [Fixture.slot("actions", Fixture.node("ActionPanel", id: 11))])
        let root = Fixture.root(Fixture.node("List", children: [Fixture.slot("actions", Fixture.node("ActionPanel", id: 12)), item]))
        let view = ViewState.view(in: root)
        let rows = ViewState.rows(of: view, searchText: "")
        #expect(ViewState.actionPanel(view: view, selectedRow: rows.first)?.id == 11)
        #expect(ViewState.actionPanel(view: view, selectedRow: nil)?.id == 12)
    }

    @Test func anEmptyListUsesItsEmptyViewsPanelThenItsOwn() {
        let empty = Fixture.node("EmptyView", children: [Fixture.slot("actions", Fixture.node("ActionPanel", id: 21))])
        let withEmptyView = Fixture.root(Fixture.node("List", children: [Fixture.slot("actions", Fixture.node("ActionPanel", id: 22)), empty]))
        #expect(ViewState.actionPanel(view: ViewState.view(in: withEmptyView), selectedRow: nil)?.id == 21)
        #expect(ViewState.actionPanel(view: Fixture.tree(Fixture.node("List")), selectedRow: nil) == nil)
        #expect(ViewState.actionPanel(view: nil, selectedRow: nil) == nil)
    }

    @Test func aDetailUsesItsOwnPanel() {
        let detail = Fixture.tree(Fixture.node("Detail", children: [Fixture.slot("actions", Fixture.node("ActionPanel", id: 31))]))
        #expect(ViewState.actionPanel(view: detail, selectedRow: nil)?.id == 31)
    }

    @Test func actionsAreFlattenedInOrderThroughSectionsAndSubmenus() {
        #expect(ViewState.actions(in: Fixture.tree(panel)).map(\.id) == [1, 2, 3, 4, 6, 7])
        #expect(ViewState.actions(in: nil).isEmpty)
    }

    @Test func theMenuListsActionsAndSubmenusWithSectionTitles() {
        let entries = ViewState.menuEntries(in: Fixture.tree(panel), query: "")
        #expect(entries.map(\.id) == [1, 2, 3, 4, 5])
        #expect(entries.map(\.section) == [nil, "Copy", "Copy", "", nil], "an untitled section is still a section")
        #expect(entries.map(\.isSubmenu) == [false, false, false, false, true])
    }

    @Test func anOpenSubmenuListsOnlyItsOwnActions() throws {
        let submenu = try #require(Fixture.tree(panel).descendants(ofType: "ActionPanel.Submenu").first)
        #expect(ViewState.menuEntries(in: submenu, query: "").map(\.id) == [6, 7])
    }

    @Test func aQuerySearchesEveryActionIncludingInsideSubmenus() {
        let tree = Fixture.tree(panel)
        #expect(ViewState.menuEntries(in: tree, query: "COPY").map(\.id) == [2, 3])
        #expect(ViewState.menuEntries(in: tree, query: "high").map(\.id) == [6])
        #expect(ViewState.menuEntries(in: tree, query: "copy").allSatisfy { $0.section == nil })
        #expect(ViewState.menuEntries(in: tree, query: "nothing").isEmpty)
        #expect(ViewState.menuEntries(in: nil, query: "").isEmpty)
    }
}

struct FormStateTests {
    private let form = Fixture.node("Form", children: [
        Fixture.slot("actions", Fixture.node("ActionPanel")),
        Fixture.node("Form.Description", props: ["title": "About", "text": "No id, not a field"]),
        Fixture.node("Form.TextField", id: 1, props: ["id": "subject"]),
        Fixture.node("Form.TextArea", id: 2, props: ["id": "body", "defaultValue": "Hello"]),
        Fixture.node("Form.Checkbox", id: 3, props: ["id": "urgent"]),
        Fixture.node("Form.Dropdown", id: 4, props: ["id": "area"], children: [
            Fixture.node("Dropdown.Section", children: [Fixture.node("Dropdown.Item", props: ["value": "ui", "title": "Interface"])]),
            Fixture.node("Dropdown.Item", props: ["value": "runtime", "title": "Runtime"]),
        ]),
        Fixture.node("Form.DatePicker", id: 5, props: ["id": "due"]),
        Fixture.node("Form.TagPicker", id: 6, props: ["id": "tags"]),
        Fixture.node("Form.FilePicker", id: 7, props: ["id": "files"]),
        Fixture.node("Form.TextField", id: 8, props: ["id": "controlled", "value": "From the extension", "defaultValue": "Ignored"]),
    ])

    private var view: Node {
        Fixture.tree(form)
    }

    private func field(_ id: String) throws -> Node {
        try #require(ViewState.formFields(of: view).first { $0.props["id"] as? String == id })
    }

    @Test func fieldsAreTheChildrenWithAnId() {
        #expect(ViewState.formFields(of: view).map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(ViewState.formFields(of: Fixture.tree(Fixture.node("List"))).isEmpty)
        #expect(ViewState.formFields(of: nil).isEmpty)
    }

    @Test func aFieldsValueIsTheControlledValueThenTypedThenDefault() throws {
        #expect(try ViewState.formValue(field("controlled"), typed: ["controlled": "Typed"]) as? String == "From the extension")
        #expect(try ViewState.formValue(field("body"), typed: ["body": "Typed"]) as? String == "Typed")
        #expect(try ViewState.formValue(field("body"), typed: [:]) as? String == "Hello")
        #expect(try ViewState.formValue(field("subject"), typed: [:]) == nil)
    }

    @Test func aDropdownWithNothingChosenUsesItsFirstItem() throws {
        #expect(try ViewState.formValue(field("area"), typed: [:]) as? String == "ui")
        #expect(try ViewState.formValue(field("area"), typed: ["area": "runtime"]) as? String == "runtime")
    }

    @Test func aNodeWithoutAnIdHasNoValue() {
        #expect(ViewState.formValue(Fixture.tree(Fixture.node("Form.Separator")), typed: [:]) == nil)
    }

    @Test func submittingAnUntouchedFormSendsEachTypesEmptyValue() {
        let values = ViewState.submittedValues(of: view, typed: [:])
        #expect(values["subject"] as? String == "")
        #expect(values["body"] as? String == "Hello")
        #expect(values["urgent"] as? Bool == false)
        #expect(values["area"] as? String == "ui")
        #expect(values["due"] is NSNull)
        #expect(values["tags"] as? [String] == [])
        #expect(values["files"] as? [String] == [])
        #expect(values["controlled"] as? String == "From the extension")
        #expect(values.count == 8)
    }

    @Test func submittingSendsTypedValuesAndTagsDatesForTheHost() {
        let values = ViewState.submittedValues(of: view, typed: [
            "subject": "Crash", "urgent": true, "tags": ["bug"], "due": "2026-10-09T00:00:00Z",
        ])
        #expect(values["subject"] as? String == "Crash")
        #expect(values["urgent"] as? Bool == true)
        #expect(values["tags"] as? [String] == ["bug"])
        #expect(values["due"] as? [String: String] == ["$date": "2026-10-09T00:00:00Z"])
    }

    @Test func onlyDatePickersAreTaggedAsDates() {
        let textField = Fixture.tree(Fixture.node("Form.TextField", props: ["id": "when"]))
        #expect(ViewState.wireValue("2026-10-09T00:00:00Z", field: textField) as? String == "2026-10-09T00:00:00Z")
    }
}
