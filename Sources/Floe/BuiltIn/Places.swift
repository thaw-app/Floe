//
//  Places.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import MapKit

/// A place Apple Maps found.
nonisolated struct Place: Hashable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
}

/// "maps coffee in lisbon": places by name or address, found by Apple Maps. What is typed after the word is
/// sent to Apple to find them; nothing is sent for any other search, and Floe asks for no location.
nonisolated enum Places {
    static let keyword = "maps"
    static let rowLimit = 12

    /// What finds the places, so a test can stand in for Apple Maps.
    struct Finder: Sendable {
        var find: @Sendable (String) async -> [Place]

        static let apple = Finder { await Places.search($0) }
    }

    @MainActor
    static func search(_ text: String) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        guard let found = try? await MKLocalSearch(request: request).start() else { return [] }
        return found.mapItems.prefix(rowLimit).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            let coordinate = item.location.coordinate
            return Place(name: name, address: item.address?.shortAddress ?? item.address?.fullAddress ?? "", latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    /// The link that shows a place in the Maps app, or the way to it.
    static func link(to place: Place, directions: Bool = false) -> URL? {
        var components = URLComponents()
        components.scheme = "maps"
        components.host = ""
        let point = "\(place.latitude),\(place.longitude)"
        components.queryItems = directions
            ? [URLQueryItem(name: "daddr", value: point)]
            : [URLQueryItem(name: "q", value: place.name), URLQueryItem(name: "ll", value: point)]
        return components.url
    }
}

/// The scope waits for the typing to rest, so Apple is asked once for a search and not once a letter.
struct PlaceSearchScope: SearchScope {
    let keyword = Places.keyword
    let title = String(localized: "Places", bundle: .floe, comment: "The heading over the places Apple Maps found.")
    let emptyTitle = String(localized: "No place matches", bundle: .floe)
    var finder = Places.Finder.apple
    var pause = Duration.milliseconds(400)

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        .once(after: pause) { [finder] in await finder.find(text).map(RootItem.place) }
    }
}
