//
//  SessionAppearanceTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct SessionAppearanceTests {
    @Test func theHostIsToldWhetherTheAppIsLightOrDark() {
        let stale = ["FLOE_APPEARANCE": "dark"]
        #expect(ExtensionSession.hostVariables(stale, grants: [], isDark: false)["FLOE_APPEARANCE"] == "light")
        #expect(ExtensionSession.hostVariables([:], grants: [], isDark: true)["FLOE_APPEARANCE"] == "dark")
        #expect(ExtensionSession.hostVariables(stale, grants: [])["FLOE_APPEARANCE"] == nil, "what the shell held is not passed on")
    }
}
