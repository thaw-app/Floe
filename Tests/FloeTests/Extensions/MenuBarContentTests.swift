//
//  MenuBarContentTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct MenuBarContentTests {
    private let assets = "/tmp/floe-menu-bar-content/assets"

    private func resolver(isDark: Bool = false, scale: CGFloat = 2, files: Set<String> = [], symbols: Set<String> = []) -> MenuBarIconResolver {
        MenuBarIconResolver(assetsPath: assets, isDark: isDark, scale: scale, fileExists: { files.contains($0) }, symbolExists: { symbols.contains($0) })
    }

    private func root(_ props: [String: Any], _ children: [[String: Any]] = []) -> Node? {
        Node(json: Fixture.node("root", id: 0, children: [Fixture.node("MenuBarExtra", id: 1, props: props, children: children)]))
    }

    private func items(_ root: Node?, failure: SessionFailure? = nil) -> [MenuBarMenuItem] {
        let resolver = resolver(symbols: ["star"])
        return MenuBarMenuItem.items(root: root, failure: failure, commandTitle: "Status", icon: resolver.icon(for:))
    }

    // MARK: Status button

    @Test func theStatusButtonIsToldOnlyWhatChanged() {
        let star = MenuBarIcon.symbol("star")
        let first = MenuBarStatusContent(title: "1", icon: star, toolTip: "Tip")
        #expect(first.changes(from: nil) == [.title, .image, .toolTip], "nothing is on the button yet")
        #expect(first.changes(from: first) == [])
        #expect(MenuBarStatusContent(title: "2", icon: star, toolTip: "Tip").changes(from: first) == [.title])
        #expect(MenuBarStatusContent(title: "1", icon: .symbol("moon"), toolTip: "Tip").changes(from: first) == [.image])
        #expect(MenuBarStatusContent(title: "2", icon: nil, toolTip: "Tip").changes(from: first) == [.title, .image])
        #expect(MenuBarStatusContent(title: "1", icon: star, toolTip: "Other").changes(from: first) == [.toolTip])
    }

    @Test func theStatusContentComesFromTheMenuBarExtra() {
        let resolver = resolver(symbols: ["star"])
        let first = MenuBarStatusContent(root: root(["title": "12:00", "icon": "icon:Star", "tooltip": "Clock"]), previous: nil, icon: resolver.icon(for:))
        #expect(first == MenuBarStatusContent(title: "12:00", icon: .symbol("star"), toolTip: "Clock"))

        let second = MenuBarStatusContent(root: root(["title": "12:01"]), previous: first, icon: resolver.icon(for:))
        #expect(second == MenuBarStatusContent(title: "12:01", icon: nil, toolTip: "Clock"), "a render without a tooltip keeps the last one")

        let none = MenuBarStatusContent(root: nil, previous: nil, icon: resolver.icon(for:))
        #expect(none == MenuBarStatusContent())
    }

    @Test func aButtonWithNothingToShowFallsBackToTheCommandTitle() {
        #expect(MenuBarStatusContent().shownTitle(hasImage: false, commandTitle: "Status") == "Status")
        #expect(MenuBarStatusContent().shownTitle(hasImage: true, commandTitle: "Status").isEmpty)
        #expect(MenuBarStatusContent(title: "3").shownTitle(hasImage: false, commandTitle: "Status") == "3")
    }

    // MARK: Menu rows

    @Test func aRootMapsToRowsEndingWithTheRemoveEntry() {
        let menu = items(root(["title": "3"], [
            Fixture.node("MenuBarExtra.Item", id: 10, props: ["title": "Open", "subtitle": "Now", "tooltip": "Opens it", "icon": "icon:Star", "shortcut": ["modifiers": ["cmd", "shift"], "key": "o"]], handlers: ["onAction"]),
            Fixture.node("MenuBarExtra.Item", id: 11, props: ["title": "Idle"]),
            Fixture.node("MenuBarExtra.Separator", id: 12),
            Fixture.node("MenuBarExtra.Section", id: 20, props: ["title": "Recent"], children: [
                Fixture.node("MenuBarExtra.Item", id: 21, props: ["title": "One"], handlers: ["onAction"]),
            ]),
            Fixture.node("MenuBarExtra.Submenu", id: 30, props: ["title": "More", "icon": "icon:Star"], children: [
                Fixture.node("MenuBarExtra.Section", id: 31, props: ["title": "First"], children: [
                    Fixture.node("MenuBarExtra.Item", id: 32, props: ["title": "Two"], handlers: ["onAction"]),
                ]),
            ]),
            Fixture.node("List.Item", id: 40, props: ["title": "Not a menu row"]),
        ]))
        let submenu: [MenuBarMenuItem] = [
            MenuBarMenuItem(key: .header(31), role: .header, title: "First"),
            MenuBarMenuItem(key: .item(32), role: .action(node: 32), title: "Two"),
        ]
        #expect(menu == [
            MenuBarMenuItem(key: .item(10), role: .action(node: 10), title: "Open", subtitle: "Now", toolTip: "Opens it", icon: .symbol("star"), shortcut: .init(key: "o", flags: [.command, .shift])),
            MenuBarMenuItem(key: .item(11), role: .disabled, title: "Idle"),
            .separator,
            .separator,
            MenuBarMenuItem(key: .header(20), role: .header, title: "Recent"),
            MenuBarMenuItem(key: .item(21), role: .action(node: 21), title: "One"),
            MenuBarMenuItem(key: .submenu(30), role: .submenu(submenu), title: "More", icon: .symbol("star")),
            .separator,
            MenuBarMenuItem(key: .remove, role: .remove, title: "Remove from Menu Bar"),
        ])
    }

    @Test func aMenuWithNothingInItSaysWhy() {
        let remove = [MenuBarMenuItem.separator, MenuBarMenuItem(key: .remove, role: .remove, title: "Remove from Menu Bar")]
        let loading = MenuBarMenuItem(key: .loading, role: .disabled, title: "Loading…")
        #expect(items(nil) == [loading] + remove, "no render yet")
        #expect(items(root(["isLoading": true])) == [loading] + remove)
        #expect(items(root([:])) == [MenuBarMenuItem(key: .empty, role: .disabled, title: "Status")] + remove)

        let loaded = items(root(["isLoading": true], [Fixture.node("MenuBarExtra.Item", id: 10, props: ["title": "Kept"])]))
        #expect(loaded.first?.title == "Kept", "rows already there stay while it loads")

        let failure = SessionFailure(kind: .crashed, message: "It stopped.", details: "")
        #expect(items(root(["title": "3"]), failure: failure) == [
            MenuBarMenuItem(key: .failure, role: .disabled, title: "It stopped."),
            MenuBarMenuItem(key: .retry, role: .retry, title: "Try Again"),
        ] + remove)
    }

    // MARK: Icons

    @Test func anIconResolvesToWhatItIsDrawnFrom() {
        let light = resolver(files: ["\(assets)/cup.png", "\(assets)/cup@dark.png", "/abs/logo.png"], symbols: ["arrow.up.circle", "star"])
        let dark = resolver(isDark: true, files: ["\(assets)/cup.png", "\(assets)/cup@dark.png", "\(assets)/sun.png", "\(assets)/moon.png"])
        func file(_ path: String) -> MenuBarIcon {
            .thumbnail(IconKey(source: .file(path: path), points: 16, scale: 2))
        }

        #expect(light.icon(for: "icon:ArrowUpCircle") == .symbol("arrow.up.circle"))
        #expect(light.icon(for: ["source": "icon:Star", "tintColor": "color:Red"]) == .symbol("star"))
        #expect(light.icon(for: "cup.png") == file("\(assets)/cup.png"))
        #expect(dark.icon(for: "cup.png") == file("\(assets)/cup@dark.png"))
        #expect(light.icon(for: "/abs/logo.png") == file("/abs/logo.png"))
        #expect(dark.icon(for: ["source": ["light": "sun.png", "dark": "moon.png"]]) == file("\(assets)/moon.png"))
        #expect(light.icon(for: ["fileIcon": "/Applications/Safari.app"]) == .thumbnail(IconKey(source: .workspace(path: "/Applications/Safari.app"), points: 16, scale: 2)))
        #expect(light.icon(for: "🔥") == .rendered(string: "🔥", assetsPath: assets, scale: 2))
        #expect(light.icon(for: "icon:NoSuchSymbol") == .rendered(string: "icon:NoSuchSymbol", assetsPath: assets, scale: 2))
        #expect(light.icon(for: "") == nil)
        #expect(light.icon(for: nil) == nil)
    }

    @Test func aMenuBarIconIsCachedAtSixteenPointsOnItsDisplay() {
        guard case let .thumbnail(retina)? = resolver(scale: 2, files: ["\(assets)/cup.png"]).icon(for: "cup.png") else {
            Issue.record("an asset file is a thumbnail")
            return
        }
        #expect(retina.points == 16)
        #expect(retina.pixels == 32)
        #expect(retina.cacheKey == "16.0@2.0|file:\(assets)/cup.png")

        guard case let .thumbnail(standard)? = resolver(scale: 1, files: ["\(assets)/cup.png"]).icon(for: "cup.png") else {
            Issue.record("an asset file is a thumbnail")
            return
        }
        #expect(standard.pixels == 16)
        #expect(standard != retina, "another display's scale is another bitmap")
    }

    @Test func onlySymbolsAndUnmatchedIconNamesAreTemplates() {
        #expect(MenuBarIcon.symbol("star").isTemplate)
        #expect(MenuBarIcon.rendered(string: "icon:NoSuchSymbol", assetsPath: assets, scale: 2).isTemplate)
        #expect(!MenuBarIcon.rendered(string: "🔥", assetsPath: assets, scale: 2).isTemplate)
        #expect(!MenuBarIcon.thumbnail(IconKey(source: .file(path: "/abs/logo.png"), points: 16, scale: 2)).isTemplate)
    }

    @MainActor @Test func aRowKeepsAnImagesProportionsAndTheStatusButtonSquaresIt() throws {
        let wide = try #require(MenuBarFixture.bitmap(width: 64, height: 32))
        #expect(MenuBarIconImages.size(of: wide, for: .menuItem) == NSSize(width: 32, height: 16))
        #expect(MenuBarIconImages.size(of: wide, for: .statusButton) == NSSize(width: 16, height: 16))
    }
}
