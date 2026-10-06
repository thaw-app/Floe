//
//  CalculationPreview+Testing.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe

/// Lets a test write `evaluatePreview("2+2") == "4"`: a preview compares as its result, and a literal is a preview with that result.
extension CalculationPreview: ExpressibleByStringLiteral, CustomStringConvertible {
    public init(stringLiteral value: String) {
        self.init(result: value)
    }

    public var description: String {
        result
    }
}
