//
//  RaycastExportTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct RaycastExportTests {
    @Test func aQuicklinksExportGivesItsLinks() {
        let file = Data("""
        [
          { "link": "https://duckduckgo.com/?q={argument}", "name": "Search DuckDuckGo" },
          { "openWith": "Finder", "iconName": "folder-16", "link": "~/Downloads", "name": "Downloads" }
        ]
        """.utf8)
        #expect(RaycastExport.read(file, passphrase: nil) == .quicklinks([
            RaycastQuicklink(name: "Search DuckDuckGo", link: "https://duckduckgo.com/?q={argument}"),
            RaycastQuicklink(name: "Downloads", link: "~/Downloads", openWith: "Finder", iconName: "folder-16"),
        ]))
    }

    @Test func aLinkWithoutANameOrAddressIsLeftOut() {
        let file = Data(#"[{ "name": "", "link": "https://a.example" }, { "name": "B" }, { "name": "C", "link": "https://c.example" }]"#.utf8)
        #expect(RaycastExport.read(file, passphrase: nil) == .quicklinks([RaycastQuicklink(name: "C", link: "https://c.example")]))
    }

    /// Each key derivation takes seconds in a debug build, so one backup serves every case that needs a passphrase.
    @Test func aBackupOpensOnlyWithItsPassphrase() throws {
        let payload = """
        {
          "snippets": [{ "title": "Sign-off", "text": "Best" }],
          "quicklinks": {
            "openWithPlatforms": [{ "id": "safari", "macos": "/Applications/Safari.app" }],
            "quicklinks": [
              { "name": "Docs", "link": "https://docs.example/?q={Query}", "openWith": "safari", "iconName": "book-16" },
              { "name": "Repo", "link": "https://github.com", "openWith": "/Applications/Arc.app" },
              { "name": "Plain", "link": "https://plain.example", "openWith": "unknown-id" }
            ]
          }
        }
        """
        let file = try RaycastBackup.make(payload: payload, passphrase: "correct horse")

        #expect(RaycastExport.read(file, passphrase: nil) == .needsPassphrase)
        #expect(RaycastExport.read(file, passphrase: "wrong") == .wrongPassphrase)
        #expect(RaycastExport.read(file, passphrase: "correct horse") == .quicklinks([
            RaycastQuicklink(name: "Docs", link: "https://docs.example/?q={Query}", openWith: "/Applications/Safari.app", iconName: "book-16"),
            RaycastQuicklink(name: "Repo", link: "https://github.com", openWith: "/Applications/Arc.app"),
            RaycastQuicklink(name: "Plain", link: "https://plain.example"),
        ]))
    }

    @Test func aBackupWithoutQuicklinksHasNoneToGive() throws {
        let file = try RaycastBackup.make(payload: #"{"snippets": [{ "title": "Sign-off", "text": "Best" }]}"#, passphrase: "pass")
        #expect(RaycastExport.read(file, passphrase: "pass") == .quicklinks([]))
    }

    @Test func aBackupFromAnotherRaycastVersionIsNotRead() throws {
        var file = Data("RAYCFG3\n".utf8)
        let header = RaycastBackup.gzip(Data(#"{"schemaVersion":4,"encryption":{"iv":"00","salt":"00"}}"#.utf8))
        withUnsafeBytes(of: UInt32(header.count).littleEndian) { file.append(contentsOf: $0) }
        file.append(header)
        #expect(RaycastExport.read(file, passphrase: "anything") == .notAnExport)
    }

    @Test func aCutOffBackupIsNotRead() {
        var file = Data("RAYCFG3\n".utf8)
        withUnsafeBytes(of: UInt32(5000).littleEndian) { file.append(contentsOf: $0) }
        #expect(RaycastExport.read(file, passphrase: "anything") == .notAnExport)
        #expect(RaycastExport.read(Data("RAYCFG3\n".utf8), passphrase: nil) == .notAnExport)
    }

    @Test func aFileThatIsNotAnExportIsSaidToBeOne() {
        #expect(RaycastExport.read(Data("hello".utf8), passphrase: nil) == .notAnExport)
        #expect(RaycastExport.read(Data(#"{"name": "x"}"#.utf8), passphrase: nil) == .notAnExport)
        #expect(RaycastExport.read(Data(#"[{"title": "a snippet", "text": "hi"}]"#.utf8), passphrase: nil) == .notAnExport)
    }
}
