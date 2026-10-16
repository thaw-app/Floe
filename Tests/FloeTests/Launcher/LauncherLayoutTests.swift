//
//  LauncherLayoutTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing

@MainActor
struct LauncherLayoutTests {
    private let full = NSSize(width: 750, height: 474)
    private let collapsed = NSSize(width: 750, height: LauncherPanelState.collapsedHeight)

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: MemoryDefaults())
    }

    @Test func theExtendedLayoutIsFullSizeWhateverIsOnScreen() {
        #expect(LauncherPanelState().contentSize(in: .extended) == full)
        #expect(LauncherPanelState(queryIsEmpty: false).contentSize(in: .extended) == full)
        #expect(LauncherPanelState(isRootSearch: false).contentSize(in: .extended) == full)
    }

    @Test func theCompactLayoutIsOnlyTheSearchBarUntilThereIsAQuery() {
        #expect(LauncherPanelState().contentSize(in: .compact) == collapsed)
        #expect(LauncherPanelState().isCollapsed(in: .compact))
        #expect(LauncherPanelState(queryIsEmpty: false).contentSize(in: .compact) == full)
        #expect(LauncherPanelState(queryIsEmpty: false).isCollapsed(in: .compact) == false)
        #expect(LauncherPanelState.collapsedHeight < full.height)
    }

    @Test func anythingButTheRootSearchIsFullSizeInTheCompactLayout() {
        let state = LauncherPanelState(isRootSearch: false)
        #expect(state.contentSize(in: .compact) == full, "a command with an empty search still needs its list")
        #expect(state.isCollapsed(in: .compact) == false)
    }

    @Test func theMenuBarSearchIsTheSizeOfEveryOtherModeInBothLayouts() {
        let state = LauncherPanelState(menuBarSearch: true, isRootSearch: false)
        #expect(state.contentSize(in: .extended) == LauncherPanelState.fullSize)
        #expect(state.contentSize(in: .compact) == LauncherPanelState.fullSize, "the panel does not change size on the way in")
        #expect(LauncherPanelState(menuBarSearch: true).isCollapsed(in: .compact) == false)
    }

    @Test func theWindowIsTheContentPlusTheMarginOnEverySide() {
        #expect(LauncherPanelState().windowSize(in: .extended) == NSSize(width: 830, height: 554))
        #expect(LauncherPanelState().windowSize(in: .compact) == NSSize(width: 830, height: LauncherPanelState.collapsedHeight + 80))
    }

    @Test func everyViewOtherThanTheRootSearchCountsAsNotTheRootSearch() {
        func state(setup: Bool = false, command: Bool = false, menuBar: Bool = false, clipboard: Bool = false, files: Bool = false) -> LauncherPanelState {
            LauncherPanelState(showingSetup: setup, showingCommand: command, menuBarSearch: menuBar, clipboardHistory: clipboard, fileSearch: files, queryIsEmpty: true)
        }
        #expect(state().isRootSearch)
        #expect(state(setup: true).isRootSearch == false)
        #expect(state(command: true).isRootSearch == false)
        #expect(state(menuBar: true).isRootSearch == false)
        #expect(state(clipboard: true).isRootSearch == false)
        #expect(state(files: true).isRootSearch == false)
    }

    @Test func aCollapsedPanelIsShownWithItsTopWhereTheFullPanelsTopWouldBe() {
        let screen = NSRect(x: 100, y: 50, width: 1600, height: 1000)
        let state = LauncherPanelState()
        let fullOrigin = state.origin(in: screen, panelSize: state.windowSize(in: .extended))
        let collapsedSize = state.windowSize(in: .compact)
        let collapsedOrigin = state.origin(in: screen, panelSize: collapsedSize)
        #expect(fullOrigin == NSPoint(x: 485, y: 393), "centered on 62% of the screen's height, as before")
        #expect(collapsedOrigin.y + collapsedSize.height == fullOrigin.y + 554)
        #expect(collapsedOrigin.x == fullOrigin.x)
    }

    @Test func theMenuBarSearchOpensWhereTheRootSearchIs() {
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let state = LauncherPanelState(menuBarSearch: true, isRootSearch: false)
        let root = LauncherPanelState(queryIsEmpty: false)
        #expect(state.origin(in: screen, panelSize: state.windowSize(in: .compact)) == root.origin(in: screen, panelSize: root.windowSize(in: .compact)))
    }

    @Test func resizingAWindowKeepsItsTopEdgeAndCenter() {
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 830, height: 554), styleMask: [.borderless], backing: .buffered, defer: true)
        window.resizeKeepingTop(to: NSSize(width: 830, height: 147))
        #expect(window.frame == NSRect(x: -4000, y: -3593, width: 830, height: 147))
        window.resizeKeepingTop(to: NSSize(width: 680, height: 480))
        #expect(window.frame == NSRect(x: -3925, y: -3926, width: 680, height: 480))
    }

    @Test func onlyTheKeysThatActOnARowAreHeldBackWhileCollapsed() {
        #expect(LauncherPanelState.isRowKey(36, flags: []), "Return")
        #expect(LauncherPanelState.isRowKey(125, flags: []), "Down")
        #expect(LauncherPanelState.isRowKey(40, flags: .command), "Command-K")
        #expect(LauncherPanelState.isRowKey(3, flags: [.command, .shift]), "Command-Shift-F")
        #expect(LauncherPanelState.isRowKey(40, flags: []) == false, "a typed k still reaches the search field")
        #expect(LauncherPanelState.isRowKey(3, flags: []) == false, "and so does a typed f")
        #expect(LauncherPanelState.isRowKey(53, flags: []) == false, "Escape still closes the panel")
        #expect(LauncherPanelState.isRowKey(43, flags: .command) == false, "Command-Comma still opens Settings")
    }

    @Test func thePanelSizeFollowsTheQueryTheViewAndTheSetting() {
        let settings = makeSettings()
        settings.clipboardHistoryIsParked = false
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []))
        var sizes: [NSSize] = []
        let subscription = model.panelWindowSizes(settings: settings).sink { sizes.append($0) }
        defer { subscription.cancel() }
        let fullWindow = NSSize(width: 830, height: 554)
        let collapsedWindow = NSSize(width: 830, height: LauncherPanelState.collapsedHeight + 80)

        settings.launcherLayout = .compact
        model.query = "co"
        model.query = "con"
        model.query = ""
        model.openClipboardHistory()
        model.closeClipboardHistory()
        settings.launcherLayout = .extended

        #expect(sizes == [fullWindow, collapsedWindow, fullWindow, collapsedWindow, fullWindow, collapsedWindow, fullWindow])
        #expect(model.panelState == LauncherPanelState())
    }
}
