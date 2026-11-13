import AppKit
@testable import Floe
import Testing

@MainActor
@Suite("A list's dropdown")
struct DropdownMenuTests {
    private func item(_ title: String, _ value: String) -> [String: Any] {
        ["type": "List.Dropdown.Item", "id": 1, "props": ["title": title, "value": value]]
    }

    /// What a click on the item does. The menu's own `performActionForItem` needs a running app to deliver it.
    private func pick(_ menu: NSMenu, at index: Int) {
        let item = menu.items[index]
        guard let action = item.action else { return }
        _ = item.target?.perform(action, with: item)
    }

    private func dropdown(_ children: [[String: Any]], value: String? = nil) throws -> Node {
        var props: [String: Any] = ["tooltip": "Select Category"]
        props["value"] = value
        return try #require(Node(json: ["type": "List.Dropdown", "id": 9, "props": props, "children": children]))
    }

    @Test func theItemsAreReadInOrderWithEachSectionUnderItsTitle() throws {
        let node = try dropdown([
            item("All", "all"),
            ["type": "List.Dropdown.Section", "id": 2, "props": ["title": "Regions"], "children": [item("Greece", "gr"), item("Texas", "tx")]],
            ["type": "List.Dropdown.Section", "id": 3, "props": [:], "children": [item("Chaos Index", "chaos")]],
        ])
        let entries = DropdownMenu.entries(for: node)
        #expect(entries == [
            .item(title: "All", value: "all"), .heading("Regions"), .item(title: "Greece", value: "gr"), .item(title: "Texas", value: "tx"),
            .untitled, .item(title: "Chaos Index", value: "chaos"),
        ])
        #expect(DropdownMenu.title(of: "tx", in: entries) == "Texas")
        #expect(DropdownMenu.title(of: "missing", in: entries) == nil)
        #expect(DropdownMenu.title(of: nil, in: entries) == nil)
    }

    @Test func aLongDropdownBecomesAMenuWithTheChosenItemCheckedAndPickingOneSaysItsValue() throws {
        let node = try dropdown((0 ..< 190).map { item("Category \($0)", "c\($0)") }, value: "c40")
        let entries = DropdownMenu.entries(for: node)
        #expect(entries.count == 190)

        var picked: [String] = []
        let built = DropdownMenu.menu(entries, current: "c40") { picked.append($0) }
        #expect(built.menu.items.count == 190)
        #expect(built.chosen?.title == "Category 40")
        #expect(built.menu.items.filter { $0.state == .on }.map(\.title) == ["Category 40"])

        pick(built.menu, at: 120)
        #expect(picked == ["c120"])

        let none = DropdownMenu.menu(entries, current: nil) { _ in }
        #expect(none.chosen == nil)
    }

    @Test func aSectionTitleIsAHeadingThatCannotBePicked() throws {
        let node = try dropdown([
            item("All", "all"),
            ["type": "List.Dropdown.Section", "id": 2, "props": ["title": "Regions"], "children": [item("Greece", "gr")]],
        ])
        var picked: [String] = []
        let built = DropdownMenu.menu(DropdownMenu.entries(for: node), current: "all") { picked.append($0) }
        #expect(built.menu.items.map(\.title) == ["All", "", "Regions", "Greece"])
        #expect(built.menu.items[1].isSeparatorItem)
        #expect(built.menu.items[2].action == nil, "a heading does nothing")
        pick(built.menu, at: 3)
        #expect(picked == ["gr"])
    }

    @Test func aFormDropdownGroupsItsItemsUnderTheirSectionTitles() {
        let groups = DropdownMenu.groups([
            .item(title: "All", value: "all"), .heading("Regions"), .item(title: "Greece", value: "gr"), .heading("Empty"),
            .heading("Indexes"), .item(title: "Chaos Index", value: "chaos"),
        ])
        #expect(groups.map(\.title) == [nil, "Regions", "Empty", "Indexes"])
        #expect(groups.map { $0.items.map(\.value) } == [["all"], ["gr"], [], ["chaos"]])
        #expect(DropdownMenu.groups([.heading("Only")]).map(\.title) == ["Only"], "no untitled group when nothing comes before the first heading")
    }

    @Test func itemsAfterATitledSectionAreNotUnderItsTitle() throws {
        let node = try dropdown([
            ["type": "Dropdown.Section", "id": 2, "props": ["title": "Regions"], "children": [item("Greece", "gr")]],
            item("Loose", "loose"),
            ["type": "Dropdown.Section", "id": 3, "props": ["title": "Indexes"], "children": [item("Chaos Index", "chaos")]],
            ["type": "Dropdown.Section", "id": 4, "props": [:], "children": [item("Untitled", "untitled")]],
        ])
        let entries = DropdownMenu.entries(for: node)
        let groups = DropdownMenu.groups(entries)
        #expect(groups.map(\.title) == ["Regions", nil, "Indexes", nil])
        #expect(groups.map { $0.items.map(\.value) } == [["gr"], ["loose"], ["chaos"], ["untitled"]])

        let menu = DropdownMenu.menu(entries, current: nil) { _ in }.menu
        #expect(menu.items.map { $0.isSeparatorItem ? "-" : $0.title } == ["Regions", "Greece", "-", "Loose", "-", "Indexes", "Chaos Index", "-", "Untitled"])
    }

    @Test func anUntitledSectionFirstAddsNoSeparator() throws {
        let node = try dropdown([
            ["type": "Dropdown.Section", "id": 2, "props": [:], "children": [item("First", "first")]],
            ["type": "Dropdown.Section", "id": 3, "props": [:], "children": [item("Second", "second")]],
        ])
        let entries = DropdownMenu.entries(for: node)
        #expect(DropdownMenu.groups(entries).map { $0.items.map(\.value) } == [["first"], ["second"]])
        #expect(DropdownMenu.menu(entries, current: nil) { _ in }.menu.items.map { $0.isSeparatorItem ? "-" : $0.title } == ["First", "-", "Second"])
    }
}
