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
            .item(title: "Chaos Index", value: "chaos"),
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
}
