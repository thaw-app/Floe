//
//  PanelSectionsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import SwiftUI
import Testing
import ThawUI

/// Every view the panel shows, as the facts its size depends on, with an empty and a non-empty query.
private let states: [LauncherPanelState] = [true, false].flatMap { queryIsEmpty in
    [
        LauncherPanelState(showingSetup: false, showingCommand: false, menuBarSearch: false, clipboardHistory: false, fileSearch: false, queryIsEmpty: queryIsEmpty),
        LauncherPanelState(showingSetup: true, showingCommand: false, menuBarSearch: false, clipboardHistory: false, fileSearch: false, queryIsEmpty: queryIsEmpty),
        LauncherPanelState(showingSetup: false, showingCommand: true, menuBarSearch: false, clipboardHistory: false, fileSearch: false, queryIsEmpty: queryIsEmpty),
        LauncherPanelState(showingSetup: false, showingCommand: false, menuBarSearch: true, clipboardHistory: false, fileSearch: false, queryIsEmpty: queryIsEmpty),
        LauncherPanelState(showingSetup: false, showingCommand: false, menuBarSearch: false, clipboardHistory: true, fileSearch: false, queryIsEmpty: queryIsEmpty),
        LauncherPanelState(showingSetup: false, showingCommand: false, menuBarSearch: false, clipboardHistory: false, fileSearch: true, queryIsEmpty: queryIsEmpty),
        LauncherPanelState(showingSetup: false, showingCommand: false, menuBarSearch: false, clipboardHistory: false, fileSearch: false, queryIsEmpty: queryIsEmpty, askingAI: true),
    ]
}

private let cases = states.flatMap { state in LauncherLayout.allCases.map { (state, $0) } }

@MainActor
struct PanelSectionsTests {
    /// The search field's rectangle on screen: the top of the content, under the window's margin.
    private func fieldFrame(_ state: LauncherPanelState, _ layout: LauncherLayout, separate: Bool, in screen: NSRect) -> NSRect {
        let window = state.windowSize(in: layout)
        let origin = state.origin(in: screen, panelSize: window)
        let height = separate ? state.pieceHeights(in: layout).field : LauncherPanelState.collapsedHeight
        let top = origin.y + window.height - LauncherView.margin
        return NSRect(x: origin.x + LauncherView.margin, y: top - height, width: window.width - LauncherView.margin * 2, height: height)
    }

    @Test(arguments: await cases)
    func thePiecesAddUpToThePanelSoTheSwitchNeverResizesTheWindow(state: LauncherPanelState, layout: LauncherLayout) {
        let heights = state.pieceHeights(in: layout)
        #expect(heights.total == state.contentSize(in: layout).height)
        #expect(heights.isCollapsed == state.isCollapsed(in: layout))
        #expect(heights.field == LauncherPanelState.collapsedHeight)
        #expect(heights.gap == ThawSpacing.base)
        #expect(heights.results > heights.field)
    }

    @Test func theSizesAreTheseForTheRootSearchAndTheMenuBarSearch() {
        let open = PanelPieceHeights(field: 67, gap: 8, results: 399)
        #expect(LauncherPanelState().pieceHeights(in: .extended) == open)
        #expect(LauncherPanelState(queryIsEmpty: false).pieceHeights(in: .compact) == open)
        #expect(LauncherPanelState().pieceHeights(in: .compact) == PanelPieceHeights(field: 67, gap: 8, results: 399, isCollapsed: true))
        #expect(LauncherPanelState().pieceHeights(in: .compact).total == 67)
        let menuBar = LauncherPanelState(menuBarSearch: true, isRootSearch: false)
        #expect(menuBar.pieceHeights(in: .compact) == open, "the same pieces as every other mode")
    }

    @Test func collapsingKeepsTheResultsHeightSoTheFadeDoesNotMoveWhenTheyAppear() {
        let collapsed = LauncherPanelState().pieceHeights(in: .compact)
        let open = LauncherPanelState(queryIsEmpty: false).pieceHeights(in: .compact)
        #expect(collapsed.fieldSpan == open.fieldSpan)
        #expect(collapsed.resultsSpan == open.resultsSpan)
    }

    @Test func theSpansCoverThePanelFromTopToBottomWithTheGapBetween() {
        let heights = PanelPieceHeights(field: 50, gap: 10, results: 140)
        #expect(heights.fieldSpan == 0 ... 0.25)
        #expect(heights.resultsSpan == 0.3 ... 1)
    }

    @Test(arguments: await cases)
    func theSearchFieldIsAtTheSameSpotCollapsedOrOpenAndSeparateOrNot(state: LauncherPanelState, layout: LauncherLayout) {
        let screen = NSRect(x: 100, y: 50, width: 1600, height: 1000)
        var typed = state
        typed.queryIsEmpty.toggle()
        let frames = [state, typed].flatMap { state in [true, false].map { fieldFrame(state, layout, separate: $0, in: screen) } }
        #expect(frames.allSatisfy { $0 == frames[0] }, "\(frames)")
        let extended = fieldFrame(state, .extended, separate: false, in: screen)
        #expect(frames[0] == extended, "and where the extended layout has it")
    }

    @Test func eachFieldShapeHasItsCornersForTheTwoPieces() {
        #expect(SearchFieldShape.rounded.fieldPieceRadius(height: 67) == ThawRadius.panel)
        #expect(SearchFieldShape.capsule.fieldPieceRadius(height: 67) == 33.5)
        #expect(SearchFieldShape.square.fieldPieceRadius(height: 67) == 0)
        #expect(SearchFieldShape.rounded.panelPieceRadius == ThawRadius.panel)
        #expect(SearchFieldShape.capsule.panelPieceRadius == ThawRadius.panel, "the results stay the panel's rounded rectangle under a capsule")
        #expect(SearchFieldShape.square.panelPieceRadius == 0)
        #expect(SearchFieldShape.capsule.pieceCornerStyle == .circular)
        #expect(SearchFieldShape.rounded.pieceCornerStyle == .continuous)
    }

    @Test func aRowsHighlightIsConcentricWithTheResultsPiece() {
        let look = LauncherLook(glass: LauncherGlass(style: .dynamic), tint: LauncherTint(), border: LauncherBorder(), hasShadow: true)
        let heights = LauncherPanelState().pieceHeights(in: .extended)
        func rowRadius(_ shape: SearchFieldShape) -> CGFloat {
            PanelPieces(look: look, fieldShape: shape, heights: heights).rowRadius
        }
        #expect(PanelPieces.listInset == 8, "what the lists keep clear of the piece's edges")
        #expect(rowRadius(.rounded) == 16, "the piece's 24 less the 8 the list is inset by: one centre for both curves")
        #expect(rowRadius(.capsule) == 16, "the results keep the panel's corners under a capsule")
        #expect(rowRadius(.square) == ThawRadius.control, "a square piece has no curve to follow")
        #expect(EnvironmentValues().searchRowCornerRadius == ThawRadius.control, "the panel in one piece keeps a control's corners")
    }

    @Test(arguments: SearchFieldShape.allCases)
    func thePiecesTakeTheLookTheirCornersAndTheSideTheyFace(shape: SearchFieldShape) {
        let look = LauncherLook(glass: LauncherGlass(style: .dynamic), tint: LauncherTint(), border: LauncherBorder(), hasShadow: true)
        let heights = LauncherPanelState().pieceHeights(in: .extended)
        let pieces = PanelPieces(look: look, fieldShape: shape, heights: heights)

        let field = pieces.fieldAppearance(facesResults: true)
        #expect(field.glass == look.glass)
        #expect(field.border == look.border)
        #expect(field.hasShadow)
        #expect(field.cornerRadius == shape.fieldPieceRadius(height: 67))
        #expect(field.shadow == .piece(facing: .bottom), "nothing is cast into the gap")
        #expect(field.span == heights.fieldSpan)
        #expect(pieces.fieldAppearance(facesResults: false).shadow == .piece(facing: nil), "alone, its shadow is whole")

        let results = pieces.resultsAppearance()
        #expect(results.glass == look.glass)
        #expect(results.cornerRadius == shape.panelPieceRadius)
        #expect(results.shadow == .piece(facing: .top))
        #expect(results.span == heights.resultsSpan)

        let whole = pieces.wholeAppearance()
        #expect(whole.cornerRadius == shape.panelPieceRadius)
        #expect(whole.shadow == .panel)
        #expect(whole.span == 0 ... 1)
    }

    @Test func thePanelInOnePieceIsDrawnAsItAlwaysWas() {
        let look = LauncherLook(glass: LauncherGlass(), tint: LauncherTint(), border: nil, hasShadow: true)
        let appearance = LauncherPanelAppearance(look)
        #expect(appearance.cornerRadius == ThawRadius.panel)
        #expect(appearance.cornerStyle == .continuous)
        #expect(appearance.shadow == .panel)
        #expect(appearance.span == 0 ... 1)
    }

    @Test func theSwitchIsOffUntilTurnedOnAndIsStored() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-panel-sections-tests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.separatesSearchField == false)
        settings.separatesSearchField = true
        settings.save()
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).separatesSearchField)
    }

    @Test func settingsStoredBeforeTheSwitchLoadUnchangedWithItOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-panel-sections-tests-\(UUID().uuidString)"))
        let earlier = AppSettings(defaults: defaults, savesAfterEdits: false)
        earlier.launcherLayout = .compact
        earlier.searchFieldShape = .capsule
        earlier.save()
        // What an earlier version wrote: the same settings without the switch's key.
        let data = try #require(defaults.data(forKey: "settings"))
        var stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(stored.removeValue(forKey: "separatesSearchField") != nil)
        try defaults.set(JSONSerialization.data(withJSONObject: stored), forKey: "settings")

        let loaded = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(loaded.separatesSearchField == false)
        #expect(loaded.launcherLayout == .compact)
        #expect(loaded.searchFieldShape == .capsule)
    }

    @Test func theSettingsSearchFindsTheSwitch() {
        let entry = SearchIndex.appearanceEntries.first { $0.id.hasSuffix("separatesSearchField") }
        #expect(entry?.section == "Layout")
        #expect(entry?.keywords.contains("split") == true)
    }
}
