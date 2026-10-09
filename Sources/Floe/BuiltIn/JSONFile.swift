//
//  JSONFile.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A value kept as one JSON file. The stores read it each time, because Settings is another process and writes it too.
nonisolated enum JSONFile {
    /// Nil when the file is missing or does not hold the value.
    static func read<Value: Decodable>(_: Value.Type = Value.self, from file: URL) -> Value? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    static func write(_ value: some Encodable, to file: URL) {
        try? JSONEncoder().encode(value).write(to: file, options: .atomic)
    }
}

/// Text made safe to sit inside a link.
nonisolated enum LinkText {
    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Everything but letters, digits, four marks and `kept` is escaped, so no character of the text ends the link early.
    static func escaped(_ text: String, keeping kept: String = "") -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: kept))) ?? ""
    }
}
