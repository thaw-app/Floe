//
//  AppScanTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct AppScanTests {
    /// An Applications folder with the given bundles in it, each a path under the root.
    private func applications(_ bundles: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-apps-\(UUID().uuidString)")
        for bundle in bundles {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(bundle), withIntermediateDirectories: true)
        }
        return root
    }

    @Test func aWebAppABrowserInstalledIsFoundInItsFolder() throws {
        let root = try applications([
            "Notes.app",
            "Helium Apps.localized/PairDrop.app",
            "Utilities/Terminal.app",
            "Suite/Deeper/Buried.app",
            ".hidden/Secret.app",
            "Notes.app/Contents/Helpers/Helper.app",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let folders = AppEntry.folders(in: [root.path])
        #expect(folders.map { ($0 as NSString).lastPathComponent } == [root.lastPathComponent, "Helium Apps.localized", "Suite", "Utilities"])
        let found = AppEntry.scan(in: folders)
        #expect(found.map(\.name) == ["Notes", "PairDrop", "Terminal"], "one folder down and no further, and never inside a bundle or a hidden folder")
        #expect(found.first { $0.name == "PairDrop" }?.url.path.hasSuffix("Helium Apps.localized/PairDrop.app") == true)
    }

    @Test func aFolderThatIsNotThereIsNothingToScan() {
        let missing = "/floe-no-such-applications-\(UUID().uuidString)"
        #expect(AppEntry.folders(in: [missing]) == [missing])
        #expect(AppEntry.scan(in: [missing]).isEmpty)
    }

    @Test func thisMacsOwnFoldersIncludeUtilities() {
        #expect(AppEntry.roots.contains("/Applications"))
        #expect(AppEntry.folders().contains("/System/Applications/Utilities"))
        #expect(AppEntry.scan().contains { $0.name == "Terminal" })
    }
}
