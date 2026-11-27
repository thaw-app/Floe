//
//  FileIndexService+State.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

nonisolated extension FileIndexService.State {
    /// Two indexes as one: building until both are ready, with their names and bytes added up.
    func joined(with other: Self) -> Self {
        switch (self, other) {
        case let (.ready(names, bytes), .ready(otherNames, otherBytes)): .ready(names: names + otherNames, bytes: bytes + otherBytes)
        case (.off, _): other
        case (_, .off): self
        default: .building
        }
    }

    /// What the Privacy page shows under the switch; nil when there is nothing to say.
    var line: String? {
        switch self {
        case .off: nil
        case .building: String(localized: "Reading the names of your files…", bundle: .floe)
        case let .ready(names, bytes):
            String(
                localized: "\(names) names, \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))",
                bundle: .floe,
                comment: "How many file names Floe holds and the memory they take, such as “203,000 names, 8 MB”."
            )
        }
    }

    /// The state as one word and two numbers, for the message that tells the settings process.
    var text: String {
        switch self {
        case .off: "off"
        case .building: "building"
        case let .ready(names, bytes): "ready \(names) \(bytes)"
        }
    }

    init?(text: String) {
        let words = text.split(separator: " ")
        switch (words.first, words.count) {
        case ("off", 1): self = .off
        case ("building", 1): self = .building
        case ("ready", 3):
            guard let names = Int(words[1]), let bytes = Int(words[2]), names >= 0, bytes >= 0 else { return nil }
            self = .ready(names: names, bytes: bytes)
        default: return nil
        }
    }
}
