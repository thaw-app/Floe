//
//  CatalogLoaderTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct CatalogLoaderTests {
    /// The worker satisfies the same interface a controlled test fake would.
    @Test func theWorkerIsACatalogScanner() {
        let loader: any CatalogScanning = CatalogLoader()
        #expect(loader is CatalogLoader)
    }

    @Test func scanCommandsFindsTheDevelopmentSample() async {
        let commands = await CatalogLoader().scanCommands(includeRaycast: false)
        #expect(commands.contains { $0.extensionName == "hello" }, "the checkout's sample extensions are on the local path")
        #expect(commands.allSatisfy { $0.source == .local })
    }

    @Test func scanAppsReturnsEachAppOnceSortedAndTellsApartTheOnesThatShareAName() async {
        let apps = await CatalogLoader().scanApps()
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #expect(apps.map(\.name) == sorted.map(\.name))
        #expect(Set(apps.map(\.url)).count == apps.count)
        for (name, sharing) in Dictionary(grouping: apps, by: \.name) where sharing.count > 1 {
            #expect(Set(sharing.compactMap(\.origin)).count == sharing.count, "\(name): each of the apps that share the name says something of its own")
        }
    }

    @Test func aSnapshotCarriesItsCatalogUntouched() {
        let apps = [AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))]
        let commands = [Fixture.command("planets")]
        let snapshot = CatalogSnapshot(apps: apps, commands: commands)
        #expect(snapshot.apps.map(\.name) == apps.map(\.name))
        #expect(snapshot.apps.map(\.url) == apps.map(\.url))
        #expect(snapshot.commands.map(\.id) == commands.map(\.id))
    }
}
