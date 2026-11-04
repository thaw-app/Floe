//
//  WindowManagementTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
@testable import Floe
import Foundation
import Testing

struct WindowManagementTests {
    private typealias Desktop = WindowManagement.Desktop
    /// The main screen below a menu bar, and a second one to its right.
    private static nonisolated let main = Desktop(display: 1, space: 3, area: CGRect(x: 0, y: 25, width: 1440, height: 875), isFullScreen: false)
    private static nonisolated let side = Desktop(display: 2, space: 7, area: CGRect(x: 1440, y: 0, width: 1920, height: 1080), isFullScreen: false)

    private static func window(_ number: CGWindowID, _ frame: CGRect, fullScreen: Bool = false) -> WindowManagement.Window {
        WindowManagement.Window(
            number: number, application: ["name": "Notes", "path": "/System/Applications/Notes.app"], frame: frame,
            isFullScreen: fullScreen, canFullScreen: true, canResize: true, canMove: false, isActive: number == 1
        )
    }

    @Test func aDesktopIsNamedByItsScreenAndTheSpaceOnIt() {
        #expect(Self.main.id == "1-3")
        #expect(Desktop(display: 4, space: nil, area: .zero, isFullScreen: false).id == "4-0")
    }

    @Test func theActiveDesktopHoldsTheFocusedWindow() {
        let marked = WindowManagement.markingActive([Self.main, Self.side], focused: CGRect(x: 1500, y: 100, width: 400, height: 300), activeSpace: 3)
        #expect(marked.map(\.isActive) == [false, true])
    }

    @Test func withNoFocusedWindowTheActiveSpaceDecidesAndThenTheFirstScreen() {
        #expect(WindowManagement.markingActive([Self.main, Self.side], focused: nil, activeSpace: 7).map(\.isActive) == [false, true])
        #expect(WindowManagement.markingActive([Self.main, Self.side], focused: nil, activeSpace: nil).map(\.isActive) == [true, false])
    }

    @Test func onlyTheWindowsOnTheActiveDesktopAreListedInTheirOrder() {
        let desktops = WindowManagement.markingActive([Self.main, Self.side], focused: nil, activeSpace: 3)
        let windows = [
            Self.window(3, CGRect(x: 100, y: 100, width: 300, height: 300)),
            Self.window(2, CGRect(x: 1600, y: 100, width: 300, height: 300)),
            Self.window(1, CGRect(x: 1200, y: 100, width: 300, height: 300)),
        ]
        #expect(WindowManagement.onActiveDesktop(windows, desktops: desktops).map(\.number) == [3, 1])
        #expect(WindowManagement.onActiveDesktop(windows, desktops: []).isEmpty)
    }

    @Test func aDesktopIsDescribedAsRaycastDoes() {
        var active = Self.main
        active.isActive = true
        let json = WindowManagement.json(active)
        #expect(json["id"] as? String == "1-3")
        #expect(json["screenId"] as? String == "1")
        #expect(json["size"] as? [String: CGFloat] == ["width": 1440, "height": 875])
        #expect(json["active"] as? Bool == true)
        #expect(json["type"] as? String == "User")
        #expect(WindowManagement.json(Desktop(display: 1, space: 9, area: .zero, isFullScreen: true))["type"] as? String == "FullScreen")
    }

    @Test func aWindowIsPlacedFromTheTopLeftOfItsDesktop() throws {
        let json = WindowManagement.json(Self.window(1, CGRect(x: 1540, y: 50, width: 800, height: 600)), desktops: [Self.main, Self.side])
        let bounds = try #require(json["bounds"] as? [String: [String: CGFloat]])
        #expect(bounds["position"] == ["x": 100, "y": 50])
        #expect(bounds["size"] == ["width": 800, "height": 600])
        #expect(json["id"] as? String == "1")
        #expect(json["desktopId"] as? String == "2-7")
        #expect(json["positionable"] as? Bool == false)
        #expect(json["resizable"] as? Bool == true)
        #expect(json["active"] as? Bool == true)
        #expect((json["application"] as? [String: String])?["name"] == "Notes")
    }

    @Test func aFullScreenWindowSaysSoInsteadOfItsFrame() {
        let json = WindowManagement.json(Self.window(2, CGRect(x: 0, y: 0, width: 1440, height: 900), fullScreen: true), desktops: [Self.main])
        #expect(json["bounds"] as? String == "fullscreen")
    }

    @Test func aChangeKeepsWhatItLeavesOutAndMeasuresFromTheDesktopItNames() {
        let frame = CGRect(x: 140, y: 75, width: 500, height: 400)
        let own = Self.main.area
        #expect(WindowManagement.target(x: 10, y: 20, width: 600, height: 300, from: frame, on: own, to: own) == CGRect(x: 10, y: 45, width: 600, height: 300))
        #expect(WindowManagement.target(x: nil, y: nil, width: nil, height: 200, from: frame, on: own, to: own) == CGRect(x: 140, y: 75, width: 500, height: 200))
        #expect(WindowManagement.target(x: nil, y: nil, width: nil, height: nil, from: frame, on: own, to: Self.side.area) == CGRect(x: 1580, y: 50, width: 500, height: 400))
    }

    @Test func setWindowBoundsReadsAFrameOrFullScreen() {
        let params: [String: Any] = ["id": "42", "desktopId": "1-3", "bounds": ["position": ["x": NSNumber(value: 10)], "size": ["width": NSNumber(value: 600.5)]]]
        #expect(WindowManagement.BoundsRequest(params: params)?.change == .frame(x: 10, y: nil, width: 600.5, height: nil, desktopID: "1-3"))
        #expect(WindowManagement.BoundsRequest(params: params)?.windowNumber == 42)
        #expect(WindowManagement.BoundsRequest(params: ["id": "42", "bounds": "fullscreen"])?.change == .fullScreen)
    }

    @Test func setWindowBoundsWithoutAWindowNumberOrBoundsIsNotUnderstood() {
        #expect(WindowManagement.BoundsRequest(params: ["id": "window", "bounds": "fullscreen"]) == nil)
        #expect(WindowManagement.BoundsRequest(params: ["id": "42"]) == nil)
        #expect(WindowManagement.BoundsRequest(params: ["id": "42", "bounds": "half"]) == nil)
    }

    @Test func theRequestsAreKnownByTheirMethods() {
        #expect(HostRequest(method: "windowManagement.getDesktops", params: [:]) == .windowManagement(.desktops))
        #expect(HostRequest(method: "windowManagement.getActiveWindow", params: [:]) == .windowManagement(.activeWindow))
        #expect(HostRequest(method: "windowManagement.getWindowsOnActiveDesktop", params: [:]) == .windowManagement(.windowsOnActiveDesktop))
        let fill = WindowManagement.BoundsRequest(params: ["id": "42", "bounds": "fullscreen"])
        #expect(HostRequest(method: "windowManagement.setWindowBounds", params: ["id": "42", "bounds": "fullscreen"]) == fill.map { .windowManagement(.setBounds($0)) })
        #expect(HostRequest(method: "windowManagement.setWindowBounds", params: [:]) == nil)
        #expect(HostRequest(method: "windowManagement.close", params: [:]) == nil)
        #expect(HostRequest.windowManagement(.desktops).isOAuth == false)
    }

    @Test func theCommandIsToldWhetherItMayManageWindows() {
        #expect(ExtensionSession.hostVariables([:], preferences: nil, hasAI: false, managesWindows: true)["FLOE_WINDOWS"] == "1")
        #expect(ExtensionSession.hostVariables(["FLOE_WINDOWS": "1"], preferences: nil, hasAI: false)["FLOE_WINDOWS"] == nil)
    }
}
