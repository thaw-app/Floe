//
//  CalculatorTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import FendCore
@testable import Floe
import Foundation
import SwiftUI
import Testing

@MainActor
struct CalculatorTests {
    private let calculator = Calculator()

    @Test func unitFractionRendering() {
        // Plain string format keeps units rendering normally with slash / instead of division symbol ÷
        #expect(CalculatorFormatter.formatString("km/h") == "km/h")
        #expect(CalculatorFormatter.formatString("km / h") == "km/h")
        #expect(CalculatorFormatter.formatString("100 km/h") == "100 km/h")
        #expect(CalculatorFormatter.formatString("100 km / h") == "100 km/h")
        #expect(CalculatorFormatter.formatString("10 m/s") == "10 m/s")
        #expect(CalculatorFormatter.formatString("10 m / s") == "10 m/s")
        #expect(CalculatorFormatter.formatString("100 W / m^2") == "100 W/m²")
        #expect(CalculatorFormatter.formatString("1 kg / m^3") == "1 kg/m³")
        #expect(CalculatorFormatter.formatString("60 mph to km/h") == "60 mph to km/h")
        #expect(CalculatorFormatter.formatString("60 mph to km / h") == "60 mph to km/h")
        #expect(CalculatorFormatter.formatString("ft / s") == "ft/s")
        #expect(CalculatorFormatter.formatString("cal / g") == "cal/g")

        // Arithmetic quantity divisions retain math division symbol ÷
        #expect(CalculatorFormatter.formatString("100 m / 10 s") == "100 m ÷ 10 s")
        #expect(CalculatorFormatter.formatString("10 / 2") == "10 ÷ 2")

        // Queries and conversions evaluate properly in fend
        if let preview = calculator.evaluatePreview("60 mph to km/h") {
            #expect(!preview.result.isEmpty)
            #expect(CalculatorFormatter.formatString(preview.result).contains("km/h"))
        } else {
            Issue.record("Expected non-nil preview for 60 mph to km/h")
        }

        if let reversePreview = calculator.evaluatePreview("100 km/h to mph") {
            #expect(!reversePreview.result.isEmpty)
        } else {
            Issue.record("Expected non-nil reversePreview for 100 km/h to mph")
        }
    }

    @Test func eagerRadicalRendering() {
        // sqrt(x eagerly renders like sqrt(x)
        #expect(CalculatorFormatter.formatString("sqrt(x") == "√x")
        #expect(CalculatorFormatter.formatString("sqrt(16") == "√16")
        #expect(CalculatorFormatter.formatString("sqrt(2") == "√2")
        #expect(CalculatorFormatter.formatString("sqrt(x + 1") == "√(x + 1)")
        #expect(CalculatorFormatter.formatString("sqrt(16 + 9") == "√(16 + 9)")
        #expect(CalculatorFormatter.formatString("sqrt(") == "√")
        #expect(CalculatorFormatter.formatString("10 + sqrt(x") == "10 + √x")

        // cbrt(x eagerly renders like cbrt(x)
        #expect(CalculatorFormatter.formatString("cbrt(x") == "∛x")
        #expect(CalculatorFormatter.formatString("cbrt(8") == "∛8")
        #expect(CalculatorFormatter.formatString("cbrt(x + 1") == "∛(x + 1)")
        #expect(CalculatorFormatter.formatString("cbrt(") == "∛")

        // Fractional powers eagerly render before closing parenthesis
        #expect(CalculatorFormatter.formatString("x^(1/2") == "√x")
        #expect(CalculatorFormatter.formatString("16^(1/2") == "√16")
        #expect(CalculatorFormatter.formatString("x^(1/3") == "∛x")
        #expect(CalculatorFormatter.formatString("8^(1/3") == "∛8")
        #expect(CalculatorFormatter.formatString("x^(1/4") == "∜x")
        #expect(CalculatorFormatter.formatString("32^(1/5") == "⁵√32")
        #expect(CalculatorFormatter.formatString("x^(1/n") == "ⁿ√x")
        #expect(CalculatorFormatter.formatString("(x + 1)^(1/2") == "√(x + 1)")

        // Eager evaluation of unclosed radical expressions
        #expect(calculator.evaluatePreview("sqrt(16")?.result == "4")
        #expect(calculator.evaluatePreview("cbrt(8")?.result == "2")
        #expect(calculator.evaluatePreview("√(16")?.result == "4")
        #expect(calculator.evaluatePreview("∛(8")?.result == "2")
        #expect(calculator.evaluatePreview("16^(1/2")?.result == "4")
    }

    @Test func rootSymbolRenderingForSqrtAndCbrt() {
        #expect(CalculatorFormatter.formatString("sqrt(16)") == "√16")
        #expect(CalculatorFormatter.formatString("sqrt(x)") == "√x")
        #expect(CalculatorFormatter.formatString("sqrt(2)") == "√2")
        #expect(CalculatorFormatter.formatString("sqrt(x + 1)") == "√(x + 1)")
        #expect(CalculatorFormatter.formatString("sqrt(16 + 9)") == "√(16 + 9)")
        #expect(CalculatorFormatter.formatString("sqrt 16") == "√16")
        #expect(CalculatorFormatter.formatString("cbrt(8)") == "∛8")
        #expect(CalculatorFormatter.formatString("cbrt(x)") == "∛x")
        #expect(CalculatorFormatter.formatString("cbrt(x + 1)") == "∛(x + 1)")
        #expect(CalculatorFormatter.formatString("cbrt 8") == "∛8")
    }

    @Test func rootSymbolRenderingForFractionalPowers() {
        #expect(CalculatorFormatter.formatString("x^(1/2)") == "√x")
        #expect(CalculatorFormatter.formatString("16^(1/2)") == "√16")
        #expect(CalculatorFormatter.formatString("(x + 1)^(1/2)") == "√(x + 1)")
        #expect(CalculatorFormatter.formatString("x^(1/3)") == "∛x")
        #expect(CalculatorFormatter.formatString("8^(1/3)") == "∛8")
        #expect(CalculatorFormatter.formatString("(x + 1)^(1/3)") == "∛(x + 1)")
        #expect(CalculatorFormatter.formatString("x^(1/4)") == "∜x")
        #expect(CalculatorFormatter.formatString("16^(1/4)") == "∜16")
        #expect(CalculatorFormatter.formatString("x^(1/5)") == "⁵√x")
        #expect(CalculatorFormatter.formatString("32^(1/5)") == "⁵√32")
        #expect(CalculatorFormatter.formatString("x^(1/n)") == "ⁿ√x")
    }

    @Test func rootSymbolRenderingForDecimalPowers() {
        #expect(CalculatorFormatter.formatString("x^0.5") == "√x")
        #expect(CalculatorFormatter.formatString("16^0.5") == "√16")
        #expect(CalculatorFormatter.formatString("(x + 1)^0.5") == "√(x + 1)")
        #expect(CalculatorFormatter.formatString("(16)^0.5") == "√16")
        #expect(CalculatorFormatter.formatString("x^0.25") == "∜x")
        #expect(CalculatorFormatter.formatString("16^0.25") == "∜16")
        #expect(CalculatorFormatter.formatString("x^0.2") == "⁵√x")
        #expect(CalculatorFormatter.formatString("32^0.2") == "⁵√32")
        #expect(CalculatorFormatter.formatString("x^0.125") == "⁸√x")
        #expect(CalculatorFormatter.formatString("x^0.1") == "¹⁰√x")
        #expect(CalculatorFormatter.formatString("8^0.3333333333333333") == "∛8")
    }

    @Test func decimalAndFractionalPowersBugFix() {
        #expect(CalculatorFormatter.formatString("x^0.75") == "x⁰˙⁷⁵")
        #expect(CalculatorFormatter.formatString("x^1.5") == "x¹˙⁵")
        #expect(CalculatorFormatter.formatString("x^(2/3)") == "x⁽²ᐟ³⁾")
    }

    @Test func rootEvaluationAndPreview() {
        #expect(calculator.evaluatePreview("√16")?.result == "4")
        #expect(calculator.evaluatePreview("√(16)")?.result == "4")
        #expect(calculator.evaluatePreview("∛8")?.result == "2")
        #expect(calculator.evaluatePreview("∜16")?.result == "2")
        #expect(calculator.evaluatePreview("⁵√32")?.result == "2")
        #expect(calculator.evaluatePreview("16^0.5")?.result == "4")
        #expect(calculator.evaluatePreview("16^(1/2)")?.result == "4")
        #expect(calculator.evaluatePreview("sqrt(16)")?.result == "4")
        #expect(calculator.evaluatePreview("cbrt(8)")?.result == "2")
    }

    @Test func approximationSymbolReplacement() {
        #expect(calculator.evaluatePreview("pi") == "≈ 3.1415926536")
        #expect(calculator.evaluatePreview("1/3") == "≈ 0.3333333333")
        #expect(calculator.evaluatePreview("sqrt(2)") == "≈ 1.4142135624")
    }

    @Test func precisionLimitingAndScientificNotation() {
        // Numbers up to 16 digits remain in standard decimal notation
        #expect(calculator.evaluatePreview("1234567890123456 + 0") == "1234567890123456")
        #expect(Calculator.formatResult("1234567890123456") == "1234567890123456")

        // Numbers exceeding 16 digits switch to scientific notation with at most 10 digits and ≈ symbol when rounded
        #expect(calculator.evaluatePreview("2^100") == "≈ 1.2676506e+30")
        #expect(calculator.evaluatePreview("10^50") == "1e+50")
        #expect(calculator.evaluatePreview("2^1000") == "≈ 1.071508607e+301")

        // 17-digit number rounds to 10 significant digits in scientific notation with ≈ symbol
        #expect(calculator.evaluatePreview("12345678901234567 + 0") == "≈ 1.23456789e+16")
        #expect(Calculator.formatResult("12345678901234567") == "≈ 1.23456789e+16")

        // Large numbers with units retain unit suffix
        #expect(calculator.evaluatePreview("12345678901234567890 m to km") == "≈ 1.23456789e+16 km")

        // Very small numbers exceeding 16 digits switch to scientific notation
        #expect(calculator.evaluatePreview("10^-20") == "1e-20")
        #expect(Calculator.formatResult("0.000000000000000000000001") == "1e-24")
    }

    @Test func mathEvaluationsWork() {
        #expect(calculator.evaluatePreview("2 + 2") == "4")
        #expect(calculator.evaluatePreview("100 * 5") == "500")
        #expect(calculator.evaluatePreview("sqrt(16)") == "4")
        #expect(calculator.evaluatePreview("100 - 30") == "70")
    }

    @Test func incompleteCalculationsActivateWithEmptyResult() {
        #expect(calculator.evaluatePreview("100 + ") == "")
        #expect(calculator.evaluatePreview("5 *") == "")
        #expect(calculator.evaluatePreview("1 W to ") == "")
        #expect(calculator.evaluatePreview("10W to ") == "")
        #expect(calculator.evaluatePreview("10 W to ") == "")
        #expect(calculator.evaluatePreview("10W to") == "")
        #expect(calculator.evaluatePreview("10 W to") == "")
    }

    @Test func bareQuantitiesDoNotActivate() {
        #expect(calculator.evaluatePreview("10W") == nil)
        #expect(calculator.evaluatePreview("10 W") == nil)
        #expect(calculator.evaluatePreview("5m") == nil)
        #expect(calculator.evaluatePreview("5 m") == nil)
    }

    @Test func nonBaseTenPrefixedNumbers() throws {
        // Lone prefixes without digits must not activate
        #expect(calculator.evaluatePreview("0x") == nil)
        #expect(calculator.evaluatePreview("0b") == nil)
        #expect(calculator.evaluatePreview("0o") == nil)

        // Numbers with digits convert automatically to decimal
        #expect(calculator.evaluatePreview("0x20") == "32")
        #expect(calculator.evaluatePreview("0xFF") == "255")
        #expect(calculator.evaluatePreview("0b1010") == "10")
        #expect(calculator.evaluatePreview("0o77") == "63")

        // Large numbers exceeding 64-bit bounds convert without overflow or fallthrough
        #expect(calculator.evaluatePreview("0x1000000000000000") == "≈ 1.152921505e+18")
        #expect(calculator.evaluatePreview("0x10000000000000000") == "≈ 1.844674407e+19")
        #expect(calculator.evaluatePreview("0b10000000000000000000000000000000000000000000000000000000000000000") == "≈ 1.844674407e+19")
        #expect(calculator.evaluatePreview("0o2000000000000000000000") == "≈ 1.844674407e+19")

        // Formatter displays scientific notation with base subscripts or powers
        let preview16 = try #require(calculator.evaluatePreview("0x1000000000000000"))
        #expect(CalculatorFormatter.formatString(preview16.result) == "≈ 1.152921505 × 10¹⁸")
        let preview17 = try #require(calculator.evaluatePreview("0x10000000000000000"))
        #expect(CalculatorFormatter.formatString(preview17.result) == "≈ 1.844674407 × 10¹⁹")
    }

    @Test func validUnitConversions() {
        let result = calculator.evaluatePreview("10W to kW")
        #expect(result?.result == "0.01 kW")
        #expect(result?.error == nil)
    }

    @Test func invalidUnitConversionsShowDescriptiveError() {
        // Incompatible units (e.g. Power to Temperature, Power to Energy, Power to Length)
        let powerToTemp = calculator.evaluatePreview("10W to k")
        #expect(powerToTemp != nil)
        #expect(powerToTemp?.result == "")
        #expect(powerToTemp?.error == "Cannot convert Power to Temperature.")

        let powerToEnergy = calculator.evaluatePreview("10W to kj")
        #expect(powerToEnergy != nil)
        #expect(powerToEnergy?.result == "")
        #expect(powerToEnergy?.error == "Cannot convert Power to Energy.")

        let powerToLength = calculator.evaluatePreview("10W to m")
        #expect(powerToLength != nil)
        #expect(powerToLength?.result == "")
        #expect(powerToLength?.error == "Cannot convert Power to Length.")

        // Half-typed or unknown target unit
        let powerToUnknown = calculator.evaluatePreview("10W to foo")
        #expect(powerToUnknown != nil)
        #expect(powerToUnknown?.result == "")
        #expect(powerToUnknown?.error == "Cannot convert Power to 'foo'.")
    }

    @Test func nonCalculationQueriesDoNotActivate() {
        #expect(calculator.evaluatePreview("Safari") == nil)
        #expect(calculator.evaluatePreview("Terminal") == nil)
        #expect(calculator.evaluatePreview("hello world") == nil)
    }

    @Test func variablesAreNotSupported() {
        #expect(calculator.evaluatePreview("a = 123") == nil)
        #expect(calculator.evaluatePreview("a=123") == nil)
        #expect(calculator.evaluatePreview("x = 5") == nil)
        #expect(calculator.evaluatePreview("foo = 42") == nil)
        #expect(calculator.evaluatePreview("speed = 60 mph") == nil)
    }

    @Test func trailingEqualsForcesCalculator() {
        #expect(calculator.evaluatePreview("2 + 2 =")?.result == "4")
        #expect(calculator.evaluatePreview("123 =")?.result == "123")
        #expect(calculator.evaluatePreview("0xff =")?.result == "255")
        #expect(calculator.evaluatePreview("10W =")?.result == "10 W")
        #expect(calculator.evaluatePreview("sqrt(16) =")?.result == "4")
        #expect(calculator.evaluatePreview("60 mph to km/h =")?.result != nil)

        // Incomplete expression with trailing equals
        let incomplete = calculator.evaluatePreview("1 + =")
        #expect(incomplete != nil)
        #expect(incomplete?.result == "")
        #expect(incomplete?.error == nil)

        // Lone '=' or '==' should not activate
        #expect(calculator.evaluatePreview("=") == nil)
        #expect(calculator.evaluatePreview("==") == nil)
        #expect(calculator.evaluatePreview("   =   ") == nil)
    }

    @Test func calculationTimeout() {
        // Calculation timeout with a very long calculation
        let preview = calculator.evaluatePreview("10000000!", timeoutMs: 1)
        #expect(preview != nil)
        #expect(preview?.result == "")
        #expect(preview?.error == "Calculation timed out")
    }

    @Test func userInputScientificNotationFormatting() {
        let sep = Locale.current.groupingSeparator ?? " "
        // Numbers up to 16 digits remain in standard decimal notation (with grouping separators)
        #expect(CalculatorFormatter.formatString("1234567890123456") == "1\(sep)234\(sep)567\(sep)890\(sep)123\(sep)456")

        // Exceeding 16 digits switches user input to scientific notation (at most 10 digits, ≈ prefix if rounded)
        #expect(CalculatorFormatter.formatString("12345678901234567") == "≈ 1.23456789 × 10¹⁶")
        #expect(CalculatorFormatter.formatString("12345678901234567 =") == "≈ 1.23456789 × 10¹⁶ =")
        #expect(CalculatorFormatter.formatString("12345678901234567 + 1") == "≈ 1.23456789 × 10¹⁶ + 1")
        #expect(CalculatorFormatter.formatString("100000000000000000000000000000000000000000000000000") == "10⁵⁰")

        // Exceeding 16 digits in non-decimal base user inputs switches to scientific notation in the same base
        #expect(CalculatorFormatter.formatString("0b1000000000000000000000000") == "1₂ × 2²⁴")
        #expect(CalculatorFormatter.formatString("0x1000000000000000000000000") == "1₁₆ × 16²⁴")
        #expect(CalculatorFormatter.formatString("0o1000000000000000000000000") == "1₈ × 8²⁴")
    }

    @Test func diceAndCustomFunctionsAreRejected() {
        #expect(calculator.evaluatePreview("d6") == nil)
        #expect(calculator.evaluatePreview("2d20") == nil)
        #expect(calculator.evaluatePreview("roll d6") == nil)
        #expect(calculator.evaluatePreview("x: x + 1") == nil)
        #expect(calculator.evaluatePreview("f = x: x^2") == nil)
    }

    @Test func blockHeightsMatch() {
        let normalView = CalculatorBlockView(expression: "10W to kW", result: "0.01 kW", selected: true)
        let errorView = CalculatorBlockView(expression: "10W to k", result: "", error: "Cannot convert Power to Temperature.", selected: true)
        let hostNormal = NSHostingView(rootView: normalView)
        let hostError = NSHostingView(rootView: errorView)
        hostNormal.frame = NSRect(x: 0, y: 0, width: 750, height: 200)
        hostError.frame = NSRect(x: 0, y: 0, width: 750, height: 200)
        let normalHeight = hostNormal.fittingSize.height
        let errorHeight = hostError.fittingSize.height
        #expect(normalHeight == errorHeight, Comment(rawValue: "Normal height \(normalHeight) vs Error height \(errorHeight)"))
    }

    @Test func normalizationOfSpacesAndUnits() {
        #expect(CalculatorFormatter.formatString("1*2") == "1 × 2")
        #expect(CalculatorFormatter.formatString("1 * 2") == "1 × 2")
        #expect(CalculatorFormatter.formatString("1*2") == CalculatorFormatter.formatString("1 * 2"))

        #expect(CalculatorFormatter.formatString("1W") == "1 W")
        #expect(CalculatorFormatter.formatString("1 w") == "1 W")
        #expect(CalculatorFormatter.formatString("1W") == CalculatorFormatter.formatString("1 w"))

        #expect(CalculatorFormatter.formatString("10W to kW") == CalculatorFormatter.formatString("10 W to kw"))
    }

    @Test func systemNumberingStyle() {
        let sep = Locale.current.groupingSeparator ?? " "
        let dec = Locale.current.decimalSeparator ?? "."
        #expect(CalculatorFormatter.formatString("1000000") == "1\(sep)000\(sep)000")
        #expect(CalculatorFormatter.formatString("1234567.89") == "1\(sep)234\(sep)567\(dec)89")
        #expect(CalculatorFormatter.formatString("500 + 1000") == "500 + 1\(sep)000")
    }

    @Test func operatorsInGrayAndUnicode() {
        #expect(CalculatorFormatter.formatString("10*2") == "10 × 2")
        #expect(CalculatorFormatter.formatString("10/2") == "10 ÷ 2")
        #expect(CalculatorFormatter.formatString("10-2") == "10 − 2")
        #expect(CalculatorFormatter.formatString("10+2") == "10 + 2")
        #expect(CalculatorFormatter.formatString("100 km/h") == "100 km/h")
        #expect(CalculatorFormatter.formatString("100 km / h") == "100 km/h")

        let attr = CalculatorFormatter.format("1 * 2")
        if let multRange = attr.range(of: "×") {
            #expect(attr[multRange].foregroundColor == .secondary)
        }
        if let numRange = attr.range(of: "1") {
            #expect(attr[numRange].foregroundColor == .primary)
        }

        let convAttr = CalculatorFormatter.format("10 W to kW")
        if let toRange = convAttr.range(of: "to") {
            #expect(convAttr[toRange].foregroundColor == .secondary)
        }
    }

    @Test func exponentsInSuperscript() {
        #expect(CalculatorFormatter.formatString("2^10") == "2¹⁰")
        #expect(CalculatorFormatter.formatString("10^50") == "10⁵⁰")
        #expect(CalculatorFormatter.formatString("x^2") == "x²")
        #expect(CalculatorFormatter.formatString("m^2") == "m²")
        #expect(CalculatorFormatter.formatString("ft^3") == "ft³")
        #expect(CalculatorFormatter.formatString("2^-5") == "2⁻⁵")

        #expect(CalculatorFormatter.formatString("1.267650600228229e+30") == "1.267650600228229 × 10³⁰")
        #expect(CalculatorFormatter.formatString("1e+50") == "10⁵⁰")
        #expect(CalculatorFormatter.formatString("1e-20") == "10⁻²⁰")
    }

    @Test func subscriptsFormatting() {
        #expect(CalculatorFormatter.formatString("log2(8)") == "log₂(8)")
        #expect(CalculatorFormatter.formatString("log10(100)") == "log₁₀(100)")
        #expect(CalculatorFormatter.formatString("log_2(8)") == "log₂(8)")
        #expect(CalculatorFormatter.formatString("x_1 + x_2") == "x₁ + x₂")
    }

    @Test func nonDecimalBasesFormatting() {
        #expect(CalculatorFormatter.formatString("0xFF") == "FF₁₆")
        #expect(CalculatorFormatter.formatString("0b1010") == "1010₂")
        #expect(CalculatorFormatter.formatString("0o755") == "755₈")
        #expect(CalculatorFormatter.formatString("0d42") == "42₁₀")
        // Digits <= 4 do not have grouping separators inserted
        #expect(!CalculatorFormatter.formatString("0b1010").contains(" "))

        let sep = Locale.current.groupingSeparator ?? " "
        // Binary and hex are grouped in 4s
        #expect(CalculatorFormatter.formatString("0b100000000") == "1\(sep)0000\(sep)0000₂")
        #expect(CalculatorFormatter.formatString("0x12345678") == "1234\(sep)5678₁₆")
        #expect(CalculatorFormatter.formatString("100000000₂") == "1\(sep)0000\(sep)0000₂")
        #expect(CalculatorFormatter.formatString("12345678₁₆") == "1234\(sep)5678₁₆")

        // Octal is grouped in 3s
        #expect(CalculatorFormatter.formatString("0o123456") == "123\(sep)456₈")
        #expect(CalculatorFormatter.formatString("123456₈") == "123\(sep)456₈")
    }

    @Test func baseConversionsAppendBaseSubscript() {
        let sep = Locale.current.groupingSeparator ?? " "
        let binResult = calculator.evaluatePreview("0x100 to binary")
        #expect(binResult?.result == "100000000₂")
        #expect(CalculatorFormatter.formatString(binResult?.result ?? "") == "1\(sep)0000\(sep)0000₂")

        let hexResult = calculator.evaluatePreview("0x100 to hex")
        #expect(hexResult?.result == "100₁₆")

        let octResult = calculator.evaluatePreview("256 to octal")
        #expect(octResult?.result == "400₈")

        let base16Result = calculator.evaluatePreview("256 to base 16")
        #expect(base16Result?.result == "100₁₆")

        let base2Result = calculator.evaluatePreview("256 to base 2")
        #expect(base2Result?.result == "100000000₂")
        #expect(CalculatorFormatter.formatString(base2Result?.result ?? "") == "1\(sep)0000\(sep)0000₂")

        // Decimal target base has no subscript
        let decResult = calculator.evaluatePreview("0b100 to decimal")
        #expect(decResult?.result == "4")

        // Large base conversions exceeding 16 digits switch to scientific notation in the same base
        let largeBin = calculator.evaluatePreview("2^100 to binary")
        #expect(largeBin?.result == "1₂ × 2¹⁰⁰")
        #expect(CalculatorFormatter.formatString(largeBin?.result ?? "") == "1₂ × 2¹⁰⁰")

        let largeHex = calculator.evaluatePreview("2^100 to hex")
        #expect(largeHex?.result == "1₁₆ × 16²⁵")
        #expect(CalculatorFormatter.formatString(largeHex?.result ?? "") == "1₁₆ × 16²⁵")

        let largeOct = calculator.evaluatePreview("2^100 to octal")
        #expect(largeOct?.result == "2₈ × 8³³")
        #expect(CalculatorFormatter.formatString(largeOct?.result ?? "") == "2₈ × 8³³")

        // Hexadecimal alphabetical digits are capitalized in canonical display
        let hexLetterResult = calculator.evaluatePreview("255 to hex")
        #expect(hexLetterResult?.result == "FF₁₆")
        #expect(CalculatorFormatter.formatString(hexLetterResult?.result ?? "") == "FF₁₆")

        let hexMultiByteResult = calculator.evaluatePreview("0x1a2b to hex")
        #expect(hexMultiByteResult?.result == "1A2B₁₆")
        #expect(CalculatorFormatter.formatString(hexMultiByteResult?.result ?? "") == "1A2B₁₆")

        let hexBeefResult = calculator.evaluatePreview("48879 to hex")
        #expect(hexBeefResult?.result == "BEEF₁₆")

        let hexLargeAlpha = calculator.evaluatePreview("15 * 16^20 to hex")
        #expect(hexLargeAlpha?.result == "F₁₆ × 16²⁰")
        #expect(CalculatorFormatter.formatString(hexLargeAlpha?.result ?? "") == "F₁₆ × 16²⁰")

        // Hex input formatting capitalizes alphabetical digits in expression display
        #expect(CalculatorFormatter.formatString("0xff") == "FF₁₆")
        #expect(CalculatorFormatter.formatString("0x1a2b") == "1A2B₁₆")
        #expect(CalculatorFormatter.formatString("0x1a + 0x2b") == "1A₁₆ + 2B₁₆")
        #expect(CalculatorFormatter.formatString("0xabcdef0123") == "AB\(sep)CDEF\(sep)0123₁₆")
        #expect(CalculatorFormatter.formatString("0xabcdef01234567890") == "≈ A.BCDEF0123₁₆ × 16¹⁶")
    }

    @Test func outputDisplayUsesSyntacticSpans() throws {
        // CalculationPreview preserves FendCore spans
        let preview = try #require(calculator.evaluatePreview("5 ft in meters"))
        #expect(!preview.spans.isEmpty)
        #expect(preview.spans.contains { $0.kind == .number && $0.string == "1.524" })
        #expect(preview.spans.contains { $0.kind == .identifier && $0.string.contains("meters") })
        #expect(preview.result == "1.524 meters")

        // Attributed result uses spans directly
        let attr = preview.attributedResult
        let attrString = String(attr.characters)
        #expect(attrString == "1.524 meters")
        if let numRange = attr.range(of: "1.524") {
            #expect(attr[numRange].foregroundColor == .primary)
        }
        if let unitRange = attr.range(of: "meters") {
            #expect(attr[unitRange].foregroundColor == .primary)
        }

        // Approximation span styling
        let approxPreview = try #require(calculator.evaluatePreview("1/3"))
        #expect(approxPreview.spans.contains { $0.string.hasPrefix("approx.") })
        #expect(approxPreview.result == "≈ 0.3333333333")
        let approxAttr = approxPreview.attributedResult
        if let approxRange = approxAttr.range(of: "≈") {
            #expect(approxAttr[approxRange].foregroundColor == .secondary)
        }
        if let numRange = approxAttr.range(of: "0.3333333333") {
            #expect(approxAttr[numRange].foregroundColor == .primary)
        }

        // Direct formatting from spans without string re-parsing
        let customSpans = [
            FendSpan(string: "approx. ", kind: .identifier),
            FendSpan(string: "42", kind: .number),
            FendSpan(string: " km / h", kind: .identifier),
        ]
        let formatted = Calculator.formatResult(spans: customSpans)
        #expect(formatted == "≈ 42 km/h")

        let customAttr = CalculatorFormatter.formatResult(spans: customSpans)
        #expect(String(customAttr.characters) == "≈ 42 km/h")
        if let approxRange = customAttr.range(of: "≈") {
            #expect(customAttr[approxRange].foregroundColor == .secondary)
        }
        if let numRange = customAttr.range(of: "42") {
            #expect(customAttr[numRange].foregroundColor == .primary)
        }
        if let unitRange = customAttr.range(of: "km/h") {
            #expect(customAttr[unitRange].foregroundColor == .primary)
        }
    }

    @Test func nonDecimalOutputsPreserveUnitsAndDrawSubscriptsInNumberStyle() throws {
        let sep = Locale.current.groupingSeparator ?? " "

        // 1. Non-decimal outputs preserve units in canonical result
        let hexMeterPreview = calculator.evaluatePreview("100 meters to hex")
        #expect(hexMeterPreview?.result == "64₁₆ meters")

        let binMeterPreview = calculator.evaluatePreview("100 meters to binary")
        #expect(binMeterPreview?.result == "1100100₂ meters")

        let hexBytesPreview = calculator.evaluatePreview("255 bytes to hex")
        #expect(hexBytesPreview?.result == "FF₁₆ bytes")

        // 2. Subscript is drawn in number style (.primary), NOT operator style (.secondary)
        let hexPreview = try #require(calculator.evaluatePreview("255 to hex"))
        #expect(hexPreview.result == "FF₁₆")
        let hexAttr = hexPreview.attributedResult
        if let numRange = hexAttr.range(of: "FF") {
            #expect(hexAttr[numRange].foregroundColor == .primary)
        }
        if let subRange = hexAttr.range(of: "₁₆") {
            #expect(hexAttr[subRange].foregroundColor == .primary)
        }

        // 3. Subscripts with units in attributedResult are drawn in number style and units in primary
        let hexMeterAttr = try #require(hexMeterPreview?.attributedResult)
        #expect(String(hexMeterAttr.characters) == "64₁₆ meters")
        if let numRange = hexMeterAttr.range(of: "64") {
            #expect(hexMeterAttr[numRange].foregroundColor == .primary)
        }
        if let subRange = hexMeterAttr.range(of: "₁₆") {
            #expect(hexMeterAttr[subRange].foregroundColor == .primary)
        }
        if let unitRange = hexMeterAttr.range(of: "meters") {
            #expect(hexMeterAttr[unitRange].foregroundColor == .primary)
        }

        // 4. Binary with units and grouping
        let largeBinUnitPreview = calculator.evaluatePreview("256 meters to binary")
        #expect(largeBinUnitPreview?.result == "100000000₂ meters")
        let largeBinAttr = try #require(largeBinUnitPreview?.attributedResult)
        #expect(String(largeBinAttr.characters) == "1\(sep)0000\(sep)0000₂ meters")
        if let subRange = largeBinAttr.range(of: "₂") {
            #expect(largeBinAttr[subRange].foregroundColor == .primary)
        }
        if let unitRange = largeBinAttr.range(of: "meters") {
            #expect(largeBinAttr[unitRange].foregroundColor == .primary)
        }
    }

    @Test func bibitUnitsAreDistinguishedFromBibyteUnits() {
        // String formatting preserves Mib/s and does not convert to MiB/s
        #expect(CalculatorFormatter.formatString("1 Mib/s") == "1 Mib/s")
        #expect(CalculatorFormatter.formatString("1 MiB/s") == "1 MiB/s")
        #expect(CalculatorFormatter.formatString("1 mib/s") == "1 Mib/s")

        // Other -bibit units
        #expect(CalculatorFormatter.formatString("1 Kib") == "1 Kib")
        #expect(CalculatorFormatter.formatString("1 KiB") == "1 KiB")
        #expect(CalculatorFormatter.formatString("1 kib") == "1 Kib")

        #expect(CalculatorFormatter.formatString("1 Gib") == "1 Gib")
        #expect(CalculatorFormatter.formatString("1 GiB") == "1 GiB")
        #expect(CalculatorFormatter.formatString("1 gib") == "1 Gib")

        #expect(CalculatorFormatter.formatString("1 Tib") == "1 Tib")
        #expect(CalculatorFormatter.formatString("1 TiB") == "1 TiB")
        #expect(CalculatorFormatter.formatString("1 tib") == "1 Tib")

        #expect(CalculatorFormatter.formatString("1 Pib") == "1 Pib")
        #expect(CalculatorFormatter.formatString("1 PiB") == "1 PiB")

        // Calculator evaluation
        let mibPerSecPreview = calculator.evaluatePreview("1 Mib/s")
        #expect(mibPerSecPreview?.result == "1 Mib/s")
        #expect(mibPerSecPreview.map { String($0.attributedResult.characters) } == "1 Mib/s")

        let mibBytePerSecPreview = calculator.evaluatePreview("1 MiB/s")
        #expect(mibBytePerSecPreview?.result == "1 MiB/s")
        #expect(mibBytePerSecPreview.map { String($0.attributedResult.characters) } == "1 MiB/s")

        let kibPreview = calculator.evaluatePreview("1 Kib to bits")
        #expect(kibPreview?.result == "1024 bits")

        let kibBytePreview = calculator.evaluatePreview("1 KiB to bits")
        #expect(kibBytePreview?.result == "8192 bits")

        let kibEquals = calculator.evaluatePreview("1 Kib =")
        #expect(kibEquals?.result == "1 Kib")

        let kibByteEquals = calculator.evaluatePreview("1 KiB =")
        #expect(kibByteEquals?.result == "1 KiB")

        let mibEquals = calculator.evaluatePreview("1 Mib =")
        #expect(mibEquals?.result == "1 Mib")

        let mibByteEquals = calculator.evaluatePreview("1 MiB =")
        #expect(mibByteEquals?.result == "1 MiB")
    }
}
