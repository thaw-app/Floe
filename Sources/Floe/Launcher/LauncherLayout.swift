//
//  LauncherLayout.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine
import ThawUI

/// How much of the launcher shows before anything is typed.
enum LauncherLayout: String, Codable, CaseIterable, Identifiable {
    /// The panel is always full size, with the list under the search bar.
    case extended
    /// The root search is only its search bar until there is a query.
    case compact

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .extended: String(localized: "Extended", bundle: .floe, comment: "A launcher layout: the list is always shown.")
        case .compact: String(localized: "Compact", bundle: .floe, comment: "A launcher layout: only the search field until you type.")
        }
    }
}

/// The heights of a panel drawn in two pieces: the search field's, the gap and the rest.
/// They add up to the panel's own height, so separating the pieces never resizes the window.
struct PanelPieceHeights: Equatable {
    var field: CGFloat
    var gap: CGFloat
    /// The piece under the gap, as tall as it is once the panel is open.
    var results: CGFloat
    /// Collapsed, only the field's piece is drawn.
    var isCollapsed = false

    private var open: CGFloat {
        field + gap + results
    }

    var total: CGFloat {
        isCollapsed ? field : open
    }

    /// The share of the open panel's height each piece covers, for a fade that runs down both.
    var fieldSpan: ClosedRange<CGFloat> {
        0 ... field / open
    }

    var resultsSpan: ClosedRange<CGFloat> {
        (field + gap) / open ... 1
    }
}

/// What the panel is showing, reduced to the facts its size depends on.
struct LauncherPanelState: Equatable {
    /// The menu bar item search or the search of the front app's menus.
    var menuBarSearch = false
    /// The plain root search: no setup, command, menu bar search, clipboard history, file search or answer on screen.
    var isRootSearch = true
    var queryIsEmpty = true

    static let fullSize = NSSize(width: 750, height: 474)
    /// The search bar is 65 tall with less space under it than above; 2 more evens them out.
    static let collapsedHeight: CGFloat = 67
    /// Between the two pieces: the step between siblings, so they read as one launcher.
    static let pieceGap = ThawSpacing.base

    /// Collapsed, the panel is the search bar alone.
    func isCollapsed(in layout: LauncherLayout) -> Bool {
        layout == .compact && isRootSearch && !menuBarSearch && queryIsEmpty
    }

    /// The one place the panel's size is decided.
    func contentSize(in layout: LauncherLayout) -> NSSize {
        return isCollapsed(in: layout) ? NSSize(width: Self.fullSize.width, height: Self.collapsedHeight) : Self.fullSize
    }

    /// The same height in two pieces. The field's piece is as tall as the collapsed panel,
    /// so the field is where it was whether or not the pieces are separate.
    func pieceHeights(in layout: LauncherLayout) -> PanelPieceHeights {
        let height = contentSize(in: .extended).height
        return PanelPieceHeights(
            field: Self.collapsedHeight,
            gap: Self.pieceGap,
            results: height - Self.collapsedHeight - Self.pieceGap,
            isCollapsed: isCollapsed(in: layout)
        )
    }

    /// The window is the content plus `LauncherView.margin` on every side.
    func windowSize(in layout: LauncherLayout) -> NSSize {
        let size = contentSize(in: layout)
        return NSSize(width: size.width + LauncherView.margin * 2, height: size.height + LauncherView.margin * 2)
    }

    /// Where a panel goes when it is shown. It is placed as if it were at its full height,
    /// so the search bar is at the same spot on screen whether or not the panel is collapsed.
    func origin(in visibleFrame: NSRect, panelSize: NSSize) -> NSPoint {
        let top = visibleFrame.minY + visibleFrame.height * 0.62 + windowSize(in: .extended).height / 2
        return NSPoint(x: visibleFrame.midX - panelSize.width / 2, y: top - panelSize.height)
    }

    /// Return, the arrows and their kin, and Command-K act on the selected row. The keys of its actions are held back
    /// where they are looked up (ActionKeys.handle).
    static func isRowKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 36: true
        case 40: flags.contains(.command)
        default: Shortcuts.navigationDelta(keyCode) != nil
        }
    }
}

extension LauncherModel {
    var panelState: LauncherPanelState {
        LauncherPanelState(
            showingSetup: setup != nil,
            showingCommand: runner.session?.command.mode == "view",
            menuBarSearch: isSearchingMenuBar || menuItemSearch != nil,
            clipboardHistory: isShowingClipboardHistory,
            fileSearch: isSearchingFiles || noteDesk != nil,
            queryIsEmpty: query.isEmpty,
            askingAI: askAI != nil || question != nil
        )
    }

    /// The panel's window size, sent again whenever the view on screen, the query or the layout changes it.
    func panelWindowSizes(settings: AppSettings) -> AnyPublisher<NSSize, Never> {
        // Published values arrive before they are stored, so the state is built from what is sent.
        // Either menu search fills the panel the same way.
        let menuSearches = $isSearchingMenuBar.combineLatest($menuItemSearch.map { $0 != nil }).map { $0 || $1 }
        let views = $setup.map { $0 != nil }
            .combineLatest(runner.$session.map { $0?.command.mode == "view" }, menuSearches, $isShowingClipboardHistory)
        let searches = $isSearchingFiles.combineLatest($noteDesk.map { $0 != nil }).map { $0 || $1 }.combineLatest($askAI.combineLatest($question).map { $0 != nil || $1 != nil })
        return views.combineLatest(searches, $query.map(\.isEmpty), settings.$launcherLayout)
            .map { views, searches, queryIsEmpty, layout in
                LauncherPanelState(
                    showingSetup: views.0,
                    showingCommand: views.1,
                    menuBarSearch: views.2,
                    clipboardHistory: views.3,
                    fileSearch: searches.0,
                    queryIsEmpty: queryIsEmpty,
                    askingAI: searches.1
                )
                .windowSize(in: layout)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Collapsed, there are no rows on screen, so the keys that act on the selected row do nothing.
    func handlePanelKey(_ event: NSEvent, layout: LauncherLayout) -> Bool {
        if let question {
            return answer(question, with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if panelState.isCollapsed(in: layout), LauncherPanelState.isRowKey(event.keyCode, flags: flags) {
            return true
        }
        return handleKey(event)
    }
}

extension LauncherPanelState {
    /// Mirrors the order `LauncherView` picks its view in: anything but the last branch is not the root search.
    init(
        showingSetup: Bool,
        showingCommand: Bool,
        menuBarSearch: Bool,
        clipboardHistory: Bool,
        fileSearch: Bool,
        queryIsEmpty: Bool,
        askingAI: Bool = false
    ) {
        self.init(
            menuBarSearch: menuBarSearch,
            isRootSearch: !(showingSetup || showingCommand || menuBarSearch || clipboardHistory || fileSearch || askingAI),
            queryIsEmpty: queryIsEmpty
        )
    }
}

extension NSWindow {
    /// Keeps the top edge and horizontal center where they are, so the search bar does not move.
    func resizeKeepingTop(to size: NSSize) {
        guard frame.size != size else { return }
        setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }
}
