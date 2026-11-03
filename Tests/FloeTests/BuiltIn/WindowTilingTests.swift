//
//  WindowTilingTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
@testable import Floe
import Testing

/// Stands in for a window: it records what it was told, and never grows smaller than its minimum size.
private final nonisolated class FakeWindow: TilableWindow {
    var frame: CGRect?
    var isFullScreen = false
    var minimumSize = CGSize.zero
    var refusesResize = false
    var refusesMove = false
    var calls: [String] = []

    init(frame: CGRect?) {
        self.frame = frame
    }

    func move(to origin: CGPoint) -> Bool {
        calls.append("move")
        guard !refusesMove else { return false }
        frame?.origin = origin
        return true
    }

    func resize(to size: CGSize) -> Bool {
        calls.append("resize")
        guard !refusesResize else { return false }
        frame?.size = CGSize(width: max(size.width, minimumSize.width), height: max(size.height, minimumSize.height))
        return true
    }
}

struct WindowTilingTests {
    private static nonisolated let area = CGRect(x: 0, y: 25, width: 1000, height: 800)
    private static nonisolated let screens = [area, CGRect(x: 1000, y: 0, width: 1920, height: 1080)]
    private static nonisolated let onFirstScreen = CGRect(x: 100, y: 100, width: 300, height: 300)

    @Test(arguments: [
        (WindowTile.left, CGRect(x: 0, y: 25, width: 500, height: 800)),
        (WindowTile.right, CGRect(x: 500, y: 25, width: 500, height: 800)),
        (WindowTile.top, CGRect(x: 0, y: 25, width: 1000, height: 400)),
        (WindowTile.bottom, CGRect(x: 0, y: 425, width: 1000, height: 400)),
        (WindowTile.maximized, area),
    ])
    func aTileCoversItsPartOfTheScreen(tile: WindowTile, expected: CGRect) {
        #expect(tile.frame(in: Self.area) == expected)
    }

    @Test func tilesOnAnOddSizedScreenMeetWithNoGap() {
        let area = CGRect(x: 10, y: 20, width: 1001, height: 801)
        #expect(WindowTile.left.frame(in: area).maxX == WindowTile.right.frame(in: area).minX)
        #expect(WindowTile.right.frame(in: area).maxX == area.maxX)
        #expect(WindowTile.top.frame(in: area).maxY == WindowTile.bottom.frame(in: area).minY)
        #expect(WindowTile.bottom.frame(in: area).maxY == area.maxY)
    }

    @Test func aWindowEndsUpOnItsTile() {
        let window = FakeWindow(frame: Self.onFirstScreen)
        #expect(WindowTiling.tile(window, to: .right, screens: Self.screens) == .tiled)
        #expect(window.frame == WindowTile.right.frame(in: Self.area))
    }

    @Test func aWindowIsSizedAgainAfterItMovesSoABiggerScreenIsFilled() {
        let window = FakeWindow(frame: Self.onFirstScreen)
        _ = WindowTiling.tile(window, to: .maximized, screens: Self.screens)
        #expect(window.calls == ["resize", "move", "resize"])
    }

    @Test func aWindowStaysOnTheScreenThatHoldsMostOfIt() {
        let window = FakeWindow(frame: CGRect(x: 900, y: 100, width: 400, height: 300))
        _ = WindowTiling.tile(window, to: .left, screens: Self.screens)
        #expect(window.frame == CGRect(x: 1000, y: 0, width: 960, height: 1080))
    }

    @Test func aWindowLargerThanItsTileSlidesBackOntoTheScreen() {
        let window = FakeWindow(frame: Self.onFirstScreen)
        window.minimumSize = CGSize(width: 700, height: 500)
        #expect(WindowTiling.tile(window, to: .right, screens: Self.screens) == .tiled)
        #expect(window.frame == CGRect(x: 300, y: 25, width: 700, height: 800))
    }

    @Test func aFullScreenWindowIsLeftAlone() {
        let window = FakeWindow(frame: Self.onFirstScreen)
        window.isFullScreen = true
        #expect(WindowTiling.tile(window, to: .left, screens: Self.screens) == .fullScreen)
        #expect(window.calls.isEmpty)
    }

    @Test func aWindowWithNoFrameOrNoScreenIsNotTiled() {
        #expect(WindowTiling.tile(FakeWindow(frame: nil), to: .left, screens: Self.screens) == .noWindow)
        #expect(WindowTiling.tile(FakeWindow(frame: Self.onFirstScreen), to: .left, screens: []) == .noWindow)
    }

    @Test func aWindowThatRefusesIsReported() {
        let unresizable = FakeWindow(frame: Self.onFirstScreen)
        unresizable.refusesResize = true
        #expect(WindowTiling.tile(unresizable, to: .left, screens: Self.screens) == .refused)
        let unmovable = FakeWindow(frame: Self.onFirstScreen)
        unmovable.refusesMove = true
        #expect(WindowTiling.tile(unmovable, to: .left, screens: Self.screens) == .refused)
        #expect(unmovable.frame == Self.onFirstScreen, "a window that won't move keeps its size")
    }

    @Test func aWindowOffEveryScreenGoesToTheFirst() {
        let lost = CGRect(x: -5000, y: -5000, width: 100, height: 100)
        #expect(WindowTiling.area(for: lost, among: Self.screens) == Self.area)
    }

    @Test func aScreenBelowTheMainDisplayHasItsAreaMeasuredFromTheTop() {
        let below = CGRect(x: 0, y: -800, width: 1200, height: 775)
        #expect(WindowTiling.accessibilityArea(visibleFrame: below, mainDisplayHeight: 1000) == CGRect(x: 0, y: 1025, width: 1200, height: 775))
    }

    @Test func onlyAFailureHasALineForTheHUD() {
        #expect(WindowTiling.Outcome.tiled.message == nil)
        for outcome in [WindowTiling.Outcome.noWindow, .fullScreen, .refused] {
            #expect(outcome.message?.isEmpty == false)
        }
    }

    @Test func onlyTheWindowCommandsTile() {
        let tiling = SystemCommand.allCases.filter { $0.tile != nil }
        #expect(Set(tiling) == [.tileWindowLeft, .tileWindowRight, .tileWindowTop, .tileWindowBottom, .maximizeWindow])
        #expect(tiling.allSatisfy { $0.confirmation == nil }, "a tile is undone by choosing another")
    }

    @Test(arguments: [
        ("left half", "system:tileWindowLeft"), ("snap right", "system:tileWindowRight"), ("top half", "system:tileWindowTop"),
        ("bottom half", "system:tileWindowBottom"), ("fullscreen", "system:maximizeWindow"),
    ])
    func aWindowCommandIsFoundByWhatPeopleCallIt(query: String, id: String) {
        let results = Ranking.search(
            SystemCommand.allCases.map(RootItem.system), query: query, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }
        )
        #expect(results.first?.id == id)
    }
}
