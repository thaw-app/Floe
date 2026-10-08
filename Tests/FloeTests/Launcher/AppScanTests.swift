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

    @Test func twoAppsOfOneNameAreBothKeptAndTheSameAppTwiceIsOne() {
        let notes = AppEntry(name: "Notes", url: URL(fileURLWithPath: "/System/Applications/Notes.app"))
        let webNotes = AppEntry(name: "Notes", url: URL(fileURLWithPath: "/Users/me/Applications/Helium Apps.localized/Notes.app"))
        let safari = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))
        let safariAgain = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications/Safari.app"))
        let chess = AppEntry(name: "Chess", url: URL(fileURLWithPath: "/System/Applications/Chess.app"))
        let identifiers = [notes.url: "com.apple.Notes", webNotes.url: "net.imput.helium.app.abc", safari.url: "com.apple.Safari", safariAgain.url: "com.apple.Safari"]
        var asked: [URL] = []

        let apps = AppEntry.distinct(
            [notes, safari, chess, webNotes, safariAgain],
            identifier: { url in
                asked.append(url)
                return identifiers[url]
            },
            folderName: { $0.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: ".localized", with: "") }
        )
        #expect(apps.map(\.url) == [notes.url, webNotes.url, safari.url, chess.url])
        #expect(apps.map(\.origin) == ["Applications", "Helium Apps", nil, nil], "only the two that share a name say where they are")
        #expect(!asked.contains(chess.url), "an app with a name of its own is not opened to be told apart")
        #expect(Set(apps.map { RootItem.app($0).id }).count == 4, "each is a row of its own")
        #expect(RootItem.app(apps[1]).rowLabel == "Helium Apps")
        #expect(RootItem.app(apps[3]).rowLabel == "Application")
    }

    @Test func twoAppsShownUnderOneNameInOneFolderAreToldApartByTheirFiles() {
        let siri = AppEntry(name: "Siri", url: URL(fileURLWithPath: "/System/Applications/Siri.app"))
        let siriAI = AppEntry(name: "Siri", url: URL(fileURLWithPath: "/System/Applications/Siri AI.app"))
        let apps = AppEntry.distinct([siri, siriAI], identifier: { $0.lastPathComponent }, folderName: { _ in "Applications" })
        #expect(apps.map(\.origin) == ["Siri", "Siri AI"])
    }

    @Test func appsWithNoIdentifierAreToldApartByWhereTheyAre() {
        let first = AppEntry(name: "Tool", url: URL(fileURLWithPath: "/Applications/Tool.app"))
        let second = AppEntry(name: "Tool", url: URL(fileURLWithPath: "/Applications/Suite/Tool.app"))
        #expect(AppEntry.distinct([first, second], identifier: { _ in nil }, folderName: { _ in "x" }).count == 2)
        #expect(AppEntry.distinct([first, first], identifier: { _ in nil }, folderName: { _ in "x" }).count == 1)
    }

    @MainActor @Test func aFolderMadeLaterIsWatchedWithoutARelaunch() throws {
        let root = try applications(["Notes.app"])
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = AppFolderWatcher { /* nothing to reload */ }
        let before = watcher.watched
        watcher.watch(AppEntry.folders(in: [root.path]))
        #expect(watcher.watched.subtracting(before) == [root.path])

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Helium Apps.localized/PairDrop.app"), withIntermediateDirectories: true)
        watcher.watch(AppEntry.folders(in: [root.path]))
        #expect(watcher.watched.subtracting(before) == [root.path, root.appendingPathComponent("Helium Apps.localized").path])
        watcher.watch(AppEntry.folders(in: [root.path]))
        #expect(watcher.watched.subtracting(before).count == 2, "a folder already watched is not watched twice")
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
