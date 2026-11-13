//
//  MenuBarPresenterTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import os
import Testing

/// A status bar button that counts what is set on it.
@MainActor final class FakeStatusButton: MenuBarStatusButton {
    var titleSets = 0
    var imageSets = 0
    var toolTipSets = 0
    var title = "" {
        didSet { titleSets += 1 }
    }

    var image: NSImage? {
        didSet { imageSets += 1 }
    }

    var toolTip: String? {
        didSet { toolTipSets += 1 }
    }
}

enum MenuBarFixture {
    static let assets = "/tmp/floe-menu-bar-presenter/assets"

    static nonisolated func bitmap(width: Int = 32, height: Int = 32) -> CGImage? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }

    /// Every PNG name exists and no symbol does, so nothing depends on the disk or the system's symbols.
    static let resolver = MenuBarIconResolver(assetsPath: assets, isDark: false, scale: 2, fileExists: { $0.hasSuffix(".png") && !$0.contains("@dark") }, symbolExists: { _ in false })

    static func item(_ title: String, id: Int, icon: String? = nil, handlers: [String] = ["onAction"]) -> [String: Any] {
        var props: [String: Any] = ["title": title]
        props["icon"] = icon
        return Fixture.node("MenuBarExtra.Item", id: id, props: props, handlers: handlers)
    }

    static func root(title: String, icon: String? = "status.png", isLoading: Bool = false, _ children: [[String: Any]]) -> Node? {
        var props: [String: Any] = ["title": title, "isLoading": isLoading]
        props["icon"] = icon
        return Node(json: Fixture.node("root", id: 0, children: [Fixture.node("MenuBarExtra", id: 1, props: props, children: children)]))
    }

    /// A menu of realistic size: 20 rows and two submenus of 5, every one with an icon, 6 icons between them.
    static func largeRoot(title: String) -> Node? {
        var children = (0 ..< 20).map { item("Item \($0)", id: 100 + $0, icon: "icon\($0 % 6).png") }
        children.append(Fixture.node("MenuBarExtra.Submenu", id: 200, props: ["title": "More", "icon": "icon0.png"], children: (0 ..< 5).map { item("More \($0)", id: 210 + $0, icon: "icon\($0).png") }))
        children.append(Fixture.node("MenuBarExtra.Submenu", id: 300, props: ["title": "Other", "icon": "icon1.png"], children: (0 ..< 5).map { item("Other \($0)", id: 310 + $0, icon: "icon\($0).png") }))
        return root(title: title, children)
    }

    static func waitFor(_ label: String, _ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }
}

@MainActor
struct MenuBarPresenterTests {
    private let button = FakeStatusButton()
    private let renders = OSAllocatedUnfairLock(initialState: [String]())
    private let presenter: MenuBarPresenter

    init() {
        let renders = renders
        let cache = IconThumbnailCache { key in
            renders.withLock { $0.append(key.cacheKey) }
            return MenuBarFixture.bitmap()
        }
        presenter = MenuBarPresenter(button: button, commandTitle: "Status", images: MenuBarIconImages(cache: cache)) { MenuBarFixture.resolver }
    }

    private var renderCount: Int {
        renders.withLock(\.count)
    }

    private func open(_ menu: NSMenu) {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.delegate?.menuWillOpen?(menu)
    }

    private func close(_ menu: NSMenu) {
        menu.delegate?.menuDidClose?(menu)
    }

    private func click(_ item: NSMenuItem) throws {
        let action = try #require(item.action)
        _ = item.target?.perform(action, with: item)
    }

    private var titles: [String] {
        presenter.menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    // MARK: Status button

    @Test func aNewCommandShowsItsTitleUntilItRenders() {
        #expect(button.title == "Status")
        #expect(button.image == nil)
        #expect(button.imageSets == 0)

        presenter.show(root: MenuBarFixture.root(title: "", icon: nil, []))
        #expect(button.title == "Status", "an extra with neither a title nor an icon keeps the name")
        #expect(button.titleSets == 1)
    }

    @Test func aRenderSetsOnlyWhatChangedOnTheButton() {
        presenter.show(root: MenuBarFixture.root(title: "1", []))
        #expect(button.title == "1")
        #expect(button.image?.size == NSSize(width: 16, height: 16))
        #expect(button.image?.isTemplate == false)
        #expect((button.titleSets, button.imageSets, button.toolTipSets) == (2, 1, 0))

        presenter.show(root: MenuBarFixture.root(title: "1", []))
        #expect((button.titleSets, button.imageSets) == (2, 1), "the same render again touches nothing")

        presenter.show(root: MenuBarFixture.root(title: "2", []))
        #expect((button.titleSets, button.imageSets) == (3, 1), "only the title")

        presenter.show(root: MenuBarFixture.root(title: "2", icon: "other.png", []))
        #expect((button.titleSets, button.imageSets) == (3, 2), "only the image")

        presenter.show(root: MenuBarFixture.root(title: "", icon: nil, []))
        #expect(button.image == nil)
        #expect(button.title == "Status")
        #expect(renderCount == 2, "one decode per icon, whatever the number of renders")
    }

    // MARK: Building the menu

    @Test func rendersWithTheMenuClosedBuildNoMenuAndLoadOneImage() async {
        for tick in 0 ..< 100 {
            presenter.show(root: MenuBarFixture.largeRoot(title: "12:00:\(tick)"))
        }
        #expect(presenter.menuBuilds == 0)
        #expect(presenter.menu.numberOfItems == 0)
        #expect(renderCount == 1, "the status image, once")
        #expect(button.titleSets == 101)
        #expect(button.imageSets == 1)

        open(presenter.menu)
        #expect(presenter.menuBuilds == 1)
        #expect(presenter.menu.numberOfItems == 24, "20 rows, 2 submenus, the separator and Remove from Menu Bar")
        #expect(presenter.menu.items.prefix(22).allSatisfy { $0.image != nil }, "a row whose icon is still loading holds its place")
        await MenuBarFixture.waitFor("the 6 row icons") { renderCount == 7 }
        await MenuBarFixture.waitFor("the rows have them") { presenter.menu.items.prefix(22).allSatisfy { $0.image !== MenuBarIconImages.placeholder } }
        #expect(presenter.menu.item(at: 0)?.image?.size == NSSize(width: 16, height: 16))

        close(presenter.menu)
        open(presenter.menu)
        #expect(presenter.menuBuilds == 1, "nothing changed, so nothing is built")

        presenter.show(root: MenuBarFixture.largeRoot(title: "12:01:40"))
        close(presenter.menu)
        open(presenter.menu)
        #expect(presenter.menuBuilds == 2)
        #expect(renderCount == 7, "every icon comes from the cache now")
    }

    @Test func aSubmenuIsFilledWhenItOpens() throws {
        presenter.show(root: MenuBarFixture.largeRoot(title: "1"))
        open(presenter.menu)
        let submenu = try #require(presenter.menu.item(at: 20)?.submenu)
        #expect(presenter.menu.item(at: 20)?.title == "More")
        #expect(submenu.numberOfItems == 0)

        open(submenu)
        #expect(submenu.items.map(\.title) == ["More 0", "More 1", "More 2", "More 3", "More 4"])
    }

    // MARK: An open menu

    @Test func anOpenMenuIsUpdatedInPlace() throws {
        func root(_ timer: String, results: [String]) -> Node? {
            let rows = results.map { MenuBarFixture.item($0, id: $0 == "First" ? 50 : 51) }
            let submenu = Fixture.node("MenuBarExtra.Submenu", id: 30, props: ["title": "More"], children: [MenuBarFixture.item(timer, id: 31)])
            return MenuBarFixture.root(title: "1", icon: nil, isLoading: results.isEmpty, [MenuBarFixture.item(timer, id: 10, handlers: []), MenuBarFixture.item("Stop", id: 11), submenu] + rows)
        }
        presenter.show(root: root("0:01", results: []))
        open(presenter.menu)
        let submenu = try #require(presenter.menu.item(at: 2)?.submenu)
        open(submenu)
        let before = presenter.menu.items
        #expect(titles == ["0:01", "Stop", "More", "-", "Remove from Menu Bar"])

        presenter.show(root: root("0:02", results: ["First", "Second"]))
        #expect(presenter.menuBuilds == 2)
        #expect(titles == ["0:02", "Stop", "More", "First", "Second", "-", "Remove from Menu Bar"])
        let after = presenter.menu.items
        #expect(after[0] === before[0], "the timer line changed its title, not its row")
        #expect(after[1] === before[1], "a highlighted row stays the same row")
        #expect(after[2] === before[2])
        #expect(after[2].submenu === submenu, "an open submenu is not replaced")
        #expect(submenu.items.map(\.title) == ["0:02"], "and it is kept current while open")
        #expect(after[5] === before[3])
        #expect(after[6] === before[4])

        presenter.show(root: root("0:02", results: ["Second"]))
        #expect(titles == ["0:02", "Stop", "More", "Second", "-", "Remove from Menu Bar"])
        #expect(presenter.menu.item(at: 3) === after[4], "the row that stayed is the same row")
    }

    @Test func aLoadingRowIsReplacedByTheResults() {
        open(presenter.menu)
        #expect(titles == ["Loading…", "-", "Remove from Menu Bar"])
        #expect(presenter.menu.item(at: 0)?.isEnabled == false)

        presenter.show(root: MenuBarFixture.root(title: "1", isLoading: true, []))
        #expect(titles == ["Loading…", "-", "Remove from Menu Bar"])

        presenter.show(root: MenuBarFixture.root(title: "1", [MenuBarFixture.item("Result", id: 10)]))
        #expect(titles == ["Result", "-", "Remove from Menu Bar"])
    }

    @Test func aClosedSubmenuTakesItsNewRowsWhenItOpensAgain() throws {
        func root(_ row: String) -> Node? {
            MenuBarFixture.root(title: "1", [Fixture.node("MenuBarExtra.Submenu", id: 30, props: ["title": "More"], children: [MenuBarFixture.item(row, id: 31)])])
        }
        presenter.show(root: root("Old"))
        open(presenter.menu)
        let submenu = try #require(presenter.menu.item(at: 0)?.submenu)
        open(submenu)
        close(submenu)

        presenter.show(root: root("New"))
        #expect(submenu.items.map(\.title) == ["Old"], "nobody is looking at it")
        open(submenu)
        #expect(submenu.items.map(\.title) == ["New"])
    }

    // MARK: What a row does

    @Test func rowsCarryWhatTheExtensionGaveThem() throws {
        presenter.show(root: MenuBarFixture.root(title: "1", [
            Fixture.node("MenuBarExtra.Item", id: 10, props: ["title": "Open", "subtitle": "Now", "tooltip": "Opens it", "icon": "🔥", "shortcut": ["modifiers": ["cmd"], "key": "o"]], handlers: ["onAction"]),
            MenuBarFixture.item("Idle", id: 11, handlers: []),
            Fixture.node("MenuBarExtra.Section", id: 20, props: ["title": "Recent"], children: [MenuBarFixture.item("One", id: 21)]),
        ]))
        var fired: [Int] = []
        presenter.onAction = { fired.append($0) }
        open(presenter.menu)
        #expect(titles == ["Open", "Idle", "-", "Recent", "One", "-", "Remove from Menu Bar"])

        let first = try #require(presenter.menu.item(at: 0))
        #expect(first.subtitle == "Now")
        #expect(first.toolTip == "Opens it")
        #expect(first.keyEquivalent == "o")
        #expect(first.keyEquivalentModifierMask == .command)
        #expect(first.isEnabled)
        try click(first)
        try click(#require(presenter.menu.item(at: 4)))
        #expect(fired == [10, 21])

        let idle = try #require(presenter.menu.item(at: 1))
        #expect(!idle.isEnabled)
        #expect(idle.keyEquivalent.isEmpty)
        #expect(idle.action == nil)
        #expect(presenter.menu.item(at: 3)?.isSectionHeader == true)
    }

    @Test func aRowThatGainsOrLosesItsActionIsTheSameRow() throws {
        presenter.show(root: MenuBarFixture.root(title: "1", [MenuBarFixture.item("Sync", id: 10, handlers: [])]))
        open(presenter.menu)
        let row = try #require(presenter.menu.item(at: 0))
        #expect(!row.isEnabled)

        presenter.show(root: MenuBarFixture.root(title: "1", [MenuBarFixture.item("Sync", id: 10)]))
        #expect(presenter.menu.item(at: 0) === row)
        #expect(row.isEnabled)
        #expect(row.action != nil)
    }

    @Test func aFailureOffersToTryAgainAndRemoveStaysLast() throws {
        var retried = 0
        var removed = 0
        presenter.onRetry = { retried += 1 }
        presenter.onRemove = { removed += 1 }
        presenter.show(root: MenuBarFixture.root(title: "1", [MenuBarFixture.item("Row", id: 10)]))
        presenter.show(failure: SessionFailure(kind: .crashed, message: "It stopped.", details: ""))
        #expect(presenter.menuBuilds == 0)

        open(presenter.menu)
        #expect(titles == ["It stopped.", "Try Again", "-", "Remove from Menu Bar"])
        try click(#require(presenter.menu.item(at: 1)))
        try click(#require(presenter.menu.item(at: 3)))
        #expect((retried, removed) == (1, 1))

        presenter.show(failure: nil)
        #expect(titles == ["Row", "-", "Remove from Menu Bar"])
    }

    @Test func anIconAppKitCannotDrawYetIsFilledIn() async throws {
        presenter.show(root: MenuBarFixture.root(title: "1", icon: nil, [MenuBarFixture.item("Hot", id: 10, icon: "🔥"), MenuBarFixture.item("Plain", id: 11)]))
        open(presenter.menu)
        let hot = try #require(presenter.menu.item(at: 0))
        #expect(hot.image === MenuBarIconImages.placeholder)
        #expect(presenter.menu.item(at: 1)?.image == nil)
        await MenuBarFixture.waitFor("the emoji is drawn") { hot.image !== MenuBarIconImages.placeholder }
        #expect(hot.image?.size == NSSize(width: 16, height: 16))
        #expect(renderCount == 0, "an emoji is not a thumbnail")
    }
}
