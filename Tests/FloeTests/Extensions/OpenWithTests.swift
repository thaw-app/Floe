//
//  OpenWithTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct OpenWithTests {
    @Test func theAppsForAFileAreARequestThatNeedsItsPath() {
        #expect(HostRequest(method: "environment.getApplications", params: ["path": "/tmp/a.txt"]) == .applications(path: "/tmp/a.txt"))
        #expect(HostRequest(method: "environment.getApplications", params: [:]) == nil)
        #expect(!HostRequest.applications(path: "/tmp/a.txt").isOAuth)
    }

    @Test func theAppsForAFileStartWithTheOneTheSystemWouldUseEachOnce() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("open-with-\(UUID().uuidString).txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let apps = HostRequest.applications(forFileAt: file.path)
        let preferred = try #require(NSWorkspace.shared.urlForApplication(toOpen: file), "a text file has an app on every Mac")
        #expect(apps.first?["path"] == preferred.path)
        #expect(Set(apps.compactMap { $0["path"] }).count == apps.count)
    }
}

struct QuickLookActionTests {
    private func row(_ props: [String: Any]) throws -> Row {
        try Row(node: #require(Node(json: Fixture.node("List.Item", props: props))), sectionTitle: nil)
    }

    @Test func theSelectedItemsQuickLookPathIsWhatIsPreviewed() throws {
        let url = ExtensionSession.quickLookFile(of: try row(["title": "Notes", "quickLook": ["path": "~/notes.txt", "name": "Notes"]]))
        #expect(url?.path == NSString(string: "~/notes.txt").expandingTildeInPath)
        #expect(ExtensionSession.quickLookFile(of: try row(["title": "Plain"])) == nil, "an item without one previews nothing")
        #expect(ExtensionSession.quickLookFile(of: nil) == nil)
    }
}
