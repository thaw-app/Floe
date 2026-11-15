//
//  Hexadecimal.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import Foundation

nonisolated extension Data {
    /// The bytes that hexadecimal text spells, two digits each; nil when it is not such text.
    init?(hexadecimal text: String) {
        let digits = text.compactMap(\.hexDigitValue)
        guard digits.count == text.count, digits.count.isMultiple(of: 2) else { return nil }
        self.init(stride(from: 0, to: digits.count, by: 2).map { UInt8(digits[$0] << 4 | digits[$0 + 1]) })
    }

    /// The bytes as lowercase hexadecimal, two digits each.
    var hexadecimal: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
