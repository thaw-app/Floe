//
//  SettingsSidebarRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SettingsSidebarRowsTests {
    /// Two extensions, listed out of order, the second with two commands.
    private static var commands: [ExtensionCommand] {
        let zeta: [String: Any] = ["name": "zeta", "title": "Zeta", "commands": [["name": "one", "title": "One"]]]
        let alpha: [String: Any] = ["name": "alpha", "title": "Alpha", "commands": [["name": "a", "title": "A"], ["name": "b", "title": "B"]]]
        return ExtensionCommand.commands(inManifest: Fixture.manifest(zeta), folder: URL(fileURLWithPath: "/tmp/zeta"), source: .local)
            + ExtensionCommand.commands(inManifest: Fixture.manifest(alpha), folder: URL(fileURLWithPath: "/tmp/alpha"), source: .local)
    }

    /// A row as the test reads it: a page's id, or the heading's title after a "#".
    private static func describe(_ rows: [SettingsSidebarRow]) -> [String] {
        rows.map { row in
            switch row {
            case let .heading(title): "# " + title
            case let .page(page): page.page.id
            }
        }
    }

    @Test func `groups the pages under their headings, extensions before About`() {
        let rows = SettingsSidebarRows.rows(commands: Self.commands, disabledExtensions: ["zeta"])
        #expect(Self.describe(rows) == [
            "general", "appearance", "privacy",
            "# Search", "commands", "applications", "quicklinks", "fallbacks", "snippets",
            "# Connections", "ai", "sync", "store",
            "# Extensions", "extension:alpha", "extension:zeta",
            "about",
        ])
        let dimmed = rows.compactMap { row -> String? in
            guard case let .page(page) = row, page.isDimmed else { return nil }
            return page.page.id
        }
        #expect(dimmed == ["extension:zeta"])
    }

    @Test func `leaves out the Extensions heading when none is installed`() {
        let rows = SettingsSidebarRows.rows(commands: [], disabledExtensions: [])
        #expect(!Self.describe(rows).contains("# Extensions"))
        #expect(rows.last?.page == .about)
    }

    @Test func `headings select nothing and every row has its own id`() {
        let rows = SettingsSidebarRows.rows(commands: Self.commands, disabledExtensions: [])
        for row in rows {
            if case .heading = row {
                #expect(row.page == nil)
            }
        }
        #expect(Set(rows.map(\.id)).count == rows.count)
    }
}
