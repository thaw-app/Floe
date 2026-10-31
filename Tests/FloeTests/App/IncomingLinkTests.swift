//
//  IncomingLinkTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct IncomingLinkTests {
    private func link(_ text: String, parked: Bool = false) throws -> IncomingLink {
        try IncomingLink(url: #require(URL(string: text)), oauthIsParked: parked)
    }

    @Test(arguments: ["floe://oauth?state=a", "FLOE://OAuth", "raycast://oauth?state=a", "com.raycast:/oauth?state=a", "COM.RAYCAST:/OAUTH"])
    func aSignInsReturnIsOAuthUnlessParked(text: String) throws {
        #expect(try link(text) == .oauth)
        #expect(try link(text, parked: true) == .ignored)
    }

    @Test(arguments: ["floe://thaw-appearance", "FLOE://Thaw-Appearance?data=x"])
    func thawsAnswerIsItsOwnLink(text: String) throws {
        #expect(try link(text) == .thawAppearance)
        #expect(try link(text, parked: true) == .thawAppearance)
    }

    @Test(arguments: ["raycast://extensions/a/b/c", "raycast://", "com.raycast://oauth", "com.raycast:/other"])
    func anotherRaycastLinkGoesToRaycast(text: String) throws {
        #expect(try link(text) == .raycast)
        #expect(try link(text, parked: true) == .raycast)
    }

    @Test(arguments: ["floe://", "floe:oauth", "floe://settings", "thaw://oauth", "https://oauth/", "https://thaw-appearance/"])
    func anythingElseIsIgnored(text: String) throws {
        #expect(try link(text) == .ignored)
    }

    @Test func aReturnsStateIsRead() throws {
        #expect(try IncomingLink.oauthState(of: #require(URL(string: "floe://oauth?code=1&state=abc"))) == "abc")
        #expect(try IncomingLink.oauthState(of: #require(URL(string: "com.raycast:/oauth?state=abc"))) == "abc")
        #expect(try IncomingLink.oauthState(of: #require(URL(string: "floe://oauth?state=a&state=b"))) == "a")
    }

    @Test(arguments: ["floe://oauth", "floe://oauth?code=1", "https://oauth/?state=abc", "floe://thaw-appearance?state=abc", "raycast://extensions?state=abc"])
    func anythingElseHasNoState(text: String) throws {
        #expect(try IncomingLink.oauthState(of: #require(URL(string: text))) == nil)
    }
}
