//
//  PlacesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor struct PlacesTests {
    private let cafe = Place(name: "Café A Brasileira", address: "Rua Garrett 120, Lisbon", latitude: 38.7107, longitude: -9.1421)

    @Test func aPlaceOpensInMapsByItsNameAndPointAndTheWayThereByThePoint() throws {
        let shown = try #require(Places.link(to: cafe))
        #expect(shown.scheme == "maps")
        let items = URLComponents(url: shown, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "q" }?.value == "Café A Brasileira")
        #expect(items?.first { $0.name == "ll" }?.value == "38.7107,-9.1421")
        let way = try #require(Places.link(to: cafe, directions: true))
        #expect(URLComponents(url: way, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) == ["daddr"])
    }

    @Test func theScopeAsksOnceTheTypingRestsAndGivesRowsOfItsOwn() async throws {
        let asked = CallLog()
        let scope = PlaceSearchScope(finder: Places.Finder { [cafe] text in
            asked.note(text)
            return [cafe]
        }, pause: .zero)
        #expect(scope.text(in: SearchContext(query: "maps coffee in lisbon")) == "coffee in lisbon")
        #expect(scope.text(in: SearchContext(query: "maps")) == nil, "the word alone asks Apple nothing")
        #expect(scope.results(for: "coffee", context: SearchContext(query: "maps coffee")).isEmpty)
        var rows: [RootItem] = []
        for await batch in try #require(scope.updates(for: "coffee in lisbon", context: SearchContext(query: "maps coffee in lisbon"))) {
            rows = batch
        }
        #expect(asked.all == ["coffee in lisbon"])
        let row = try #require(rows.first)
        #expect(row.title == "Café A Brasileira")
        #expect(row.rowLabel == "Rua Garrett 120, Lisbon")
        #expect(row.kind == "Place")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(PlaceRows().returnTitle(for: row) == "Open in Maps")
        #expect(RootItem.place(Place(name: "Nowhere", address: "", latitude: 0, longitude: 0)).rowLabel == "Place")
    }

    @Test func aSearchThatMovesOnAsksAppleNothing() async throws {
        let asked = CallLog()
        let scope = PlaceSearchScope(finder: Places.Finder { text in
            asked.note(text)
            return []
        }, pause: .seconds(30))
        let stream = try #require(scope.updates(for: "cof", context: SearchContext(query: "maps cof")))
        let reading = Task {
            for await _ in stream {
                // Nothing arrives before the pause is over.
            }
        }
        reading.cancel()
        await reading.value
        try await Task.sleep(for: .milliseconds(50))
        #expect(asked.all.isEmpty)
    }

    @Test func aPlaceOffersTheWayThereAndItsAddress() {
        let defaults = MemoryDefaults()
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        #expect(model.features.places.placeActions(for: cafe).compactMap { $0?.title } == ["Get Directions", "Copy Address"])
        #expect(model.features.places.actions(for: .place(cafe))?.count == 3)
    }
}
