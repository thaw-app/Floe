//
//  MenuBarLogicTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
@testable import Floe
import Foundation
import Testing

struct MenuBarNamingTests {
    @Test func anXPCServiceIsNotAskedForItems() {
        let tab = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        #expect(!MenuBarNaming.canOwnItems(executableURL: URL(fileURLWithPath: tab)))
        #expect(MenuBarNaming.canOwnItems(executableURL: URL(fileURLWithPath: "/Applications/Pandan.app/Contents/MacOS/Pandan")))
        #expect(MenuBarNaming.canOwnItems(executableURL: nil), "a process that names no executable is still asked")
    }

    @Test func theLabelIsTheFirstNonEmptyOfTitleDescriptionAndHelp() {
        #expect(MenuBarNaming.label(title: "Pandan", description: "Other", help: nil) == "Pandan")
        #expect(MenuBarNaming.label(title: "", description: "AirDrop", help: nil) == "AirDrop")
        #expect(MenuBarNaming.label(title: nil, description: "  ", help: "Help text") == "Help text")
        #expect(MenuBarNaming.label(title: nil, description: nil, help: nil) == nil)
        #expect(MenuBarNaming.label(title: "", description: "", help: "") == nil)
    }

    @Test func onlyTheFirstLineOfAStatusReadoutIsUsed() {
        let readout = "f.lux\nColor temperature: 6500K\nSunset: 2 hours ago"
        #expect(MenuBarNaming.label(title: "", description: readout, help: nil) == "f.lux")
        #expect(MenuBarNaming.label(title: "  Padded  \nSecond", description: nil, help: nil) == "Padded")
    }

    @Test func thawsDividersAndUnnamedHostItemsAreNotListed() {
        #expect(MenuBarNaming.isListed(identifier: "Thaw.ControlItem.Hidden", label: "Divider", ownerName: "Thaw") == false)
        #expect(MenuBarNaming.isListed(identifier: nil, label: nil, ownerName: "MenuBarAgent") == false)
        #expect(MenuBarNaming.isListed(identifier: nil, label: nil, ownerName: "") == false)
    }

    @Test func namedItemsAndUnnamedItemsFromARealAppAreListed() {
        #expect(MenuBarNaming.isListed(identifier: "Thaw.Extra.AirDrop", label: "AirDrop", ownerName: "Thaw AirDrop"))
        #expect(MenuBarNaming.isListed(identifier: nil, label: "Wi-Fi", ownerName: "MenuBarAgent"))
        #expect(MenuBarNaming.isListed(identifier: nil, label: nil, ownerName: "Tailscale"), "it is shown under the app's name")
    }

    @Test func identifiersPreferTheBundleAndTheItemsOwnIdentifier() {
        #expect(MenuBarNaming.identifier(bundleIdentifier: "com.a", ownerName: "A", identifier: "status", label: "Label", index: 2) == "com.a|status")
        #expect(MenuBarNaming.identifier(bundleIdentifier: "com.a", ownerName: "A", identifier: nil, label: "Label", index: 2) == "com.a|Label")
        #expect(MenuBarNaming.identifier(bundleIdentifier: nil, ownerName: "A", identifier: nil, label: nil, index: 2) == "A|#2")
    }
}

struct MenuBarSearchRecentsTests {
    private struct Item: Identifiable {
        let id: String
    }

    private let defaults: UserDefaults
    private let recents: MenuBarSearchRecents

    init() throws {
        defaults = MemoryDefaults()
        recents = MenuBarSearchRecents(defaults: defaults)
    }

    @Test func startsEmpty() {
        #expect(recents.identifiers.isEmpty)
    }

    @Test func theMostRecentComesFirstAndRepeatsMoveToTheFront() {
        ["a", "b", "c", "a"].forEach(recents.record)
        #expect(recents.identifiers == ["a", "c", "b"])
    }

    @Test func keepsOnlyTheLastEight() {
        (1 ... 12).map(String.init).forEach(recents.record)
        #expect(recents.identifiers == ["12", "11", "10", "9", "8", "7", "6", "5"])
        #expect(recents.identifiers.count == MenuBarSearchRecents.limit)
    }

    @Test func resolvesToLiveItemsInRecencyOrderSkippingOnesThatAreGone() {
        ["gone", "tailscale", "flux"].forEach(recents.record)
        let live = [Item(id: "tailscale"), Item(id: "pandan"), Item(id: "flux")]
        #expect(recents.resolve(in: live).map(\.id) == ["flux", "tailscale"])
        #expect(recents.identifiers.contains("gone"), "a missing item stays stored in case it comes back")
    }
}
