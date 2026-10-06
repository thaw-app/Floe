//
//  Calculator+Result.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

extension Calculator {
    /// The result as the text Return copies: fend's answer with a sign for "approx.", units as Floe writes them,
    /// and the base below the line when the answer is in another one.
    static func formatResult(spans: [FendSpan], query: String? = nil) -> String {
        CalculatorFormatter.resultPieces(spans: spans, query: query, style: .copied).map(\.text).joined()
    }
}
