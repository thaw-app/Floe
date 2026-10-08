//
//  CalculatorBlockView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

struct CalculatorBlockView: View {
    let expression: String
    let result: String
    var attributedResult: AttributedString?
    var error: String?
    var selected: Bool = false

    private var badgeTitle: String {
        var expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.hasSuffix("=") {
            expr = String(expr.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        let lower = expr.lowercased()
        if lower.contains("%") {
            return String(localized: "Percentage", bundle: .floe, comment: "A label on the calculator result that says what kind of calculation it is.")
        }
        if lower.range(of: #"\b(to|in|of|into|as)\b"#, options: .regularExpression) != nil {
            return String(localized: "Conversion", bundle: .floe, comment: "A label on the calculator result that says what kind of calculation it is.")
        }
        if Calculator.shared.isNonBaseTenNumber(expr) {
            return String(localized: "Base", bundle: .floe, comment: "A label on the calculator result that says what kind of calculation it is.")
        }
        return String(localized: "Expression", bundle: .floe, comment: "A label on the calculator result that says what kind of calculation it is.")
    }

    /// Under the answer: that it is the result, or for money the day its rates are from.
    private var resultBadge: String {
        Calculator.shared.ratesDate(for: result).map {
            String(localized: "Rates of \($0)", bundle: .floe, comment: "A label under a converted amount of money. The placeholder is a date as the bank writes it, such as 2026-10-07.")
        } ?? String(localized: "Result", bundle: .floe)
    }

    var body: some View {
        Group {
            if let error, !error.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(error)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 106)
                .padding(.horizontal, 16)
            } else {
                HStack(spacing: 0) {
                    // Left: Expression
                    VStack(spacing: 8) {
                        Text(CalculatorFormatter.format(expression))
                            .font(.system(size: 26, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)

                        Text(badgeTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.12)))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)

                    // Middle: Vertical line with arrow
                    ZStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 1)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .frame(width: 30)

                    // Right: Result (matches exact view structure as non-empty state to prevent any height jumps)
                    VStack(spacing: 8) {
                        Text(result.isEmpty ? CalculatorFormatter.format("—") : (attributedResult ?? CalculatorFormatter.format(result)))
                            .font(.system(size: 26, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .opacity(result.isEmpty ? 0 : 1)

                        Text(resultBadge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.12)))
                            .opacity(result.isEmpty ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .background {
            let shape = RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
            shape
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .overlay {
                    if selected {
                        Color.clear.thawGlass(.selection(.accentColor, strength: .selected), in: shape)
                    }
                }
                .overlay {
                    shape.stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1)
                }
        }
        .padding(.horizontal, ThawSpacing.row)
    }
}
