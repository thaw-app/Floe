import Foundation
import Testing
@testable import FendCore

@Suite("FendCore Tests")
struct FendCoreTests {
    @Test("Library version is valid semver")
    func testVersion() {
        let version = Fend.version
        #expect(!version.isEmpty)
        #expect(version.contains("."))
    }

    @Test("Basic arithmetic evaluation")
    func testBasicArithmetic() throws {
        let result1 = try Fend.evaluate("1 + 1")
        #expect(result1 == "2")
        #expect(result1.string == "2")

        let result2 = try Fend.evaluate("2 * (3 + 4)")
        #expect(result2 == "14")
        #expect(result2.string == "14")

        let result3 = try Fend.evaluate("10 / 4")
        #expect(result3 == "2.5")
    }

    @Test("Unit and currency-style conversions")
    func testUnitConversions() throws {
        let length = try Fend.evaluate("5 ft in meters")
        #expect(length == "1.524 meters")

        let temp = try Fend.evaluate("100 celsius in fahrenheit")
        #expect(temp == "212 °F" || temp.contains("212"))

        let hex = try Fend.evaluate("0x20 to decimal")
        #expect(hex == "32")
    }

    @Test("Non-mutating preview")
    func testPreview() throws {
        let previewVal = Fend.preview("3 + 5")
        #expect(previewVal == "8")
        #expect(previewVal.string == "8")

        // Incomplete expression returns empty without crashing
        let incomplete = Fend.preview("3 + ")
        #expect(incomplete.isEmpty)
        #expect(incomplete.spans.isEmpty)
    }

    @Test("Context variable state and isolation")
    func testContextVariables() throws {
        let context = try FendContext()
        let assignResult = try context.evaluate("my_var = 50")
        #expect(assignResult.value == "50" || assignResult.isEmpty)

        let evalResult = try context.evaluate("my_var * 2")
        #expect(evalResult.value == "100")
        #expect(evalResult.string == "100")

        // Reset clears variables
        context.reset()
        #expect(throws: FendError.self) {
            try context.evaluate("my_var * 2")
        }
    }

    @Test("Invalid expression throws evaluation error")
    func testInvalidExpression() throws {
        let context = try FendContext()
        #expect(throws: FendError.self) {
            try context.evaluate("not a valid expression @#$%^&*")
        }
    }

    @Test("Variable serialization round trip")
    func testSerializationRoundTrip() throws {
        let ctx1 = try FendContext()
        _ = try ctx1.evaluate("saved_const = 99")

        let data = try ctx1.serializeVariables()
        #expect(!data.isEmpty)

        let ctx2 = try FendContext()
        try ctx2.deserializeVariables(from: data)

        let result = try ctx2.evaluate("saved_const + 1")
        #expect(result.value == "100")
    }

    @Test("Completions for prefix")
    func testCompletions() {
        let completions = Fend.completions(for: "sq")
        #expect(!completions.isEmpty)
        #expect(completions.contains { $0.display.contains("sqm") || $0.display.contains("sqft") })
    }

    // MARK: - Spans Tests

    @Test("Spans for basic arithmetic")
    func testSpansBasicArithmetic() throws {
        let result = try Fend.evaluate("1 + 1")
        #expect(result.spans.count == 1)

        let span = result.spans[0]
        #expect(span.string == "2")
        #expect(span.kind == .number)
        #expect(span.isNumber)
        #expect(!span.isWhitespace)
        #expect(!span.isIdentifier)
    }

    @Test("Spans for unit conversions")
    func testSpansUnitConversions() throws {
        let result = try Fend.evaluate("5 ft in meters")
        #expect(result.spans.count >= 2)

        let first = result.spans[0]
        #expect(first.isNumber)
        #expect(first.string == "1.524")

        let last = result.spans.last!
        #expect(last.isIdentifier)
        #expect(last.string.contains("meters"))
    }

    @Test("Spans in non-mutating preview")
    func testSpansPreview() {
        let preview = Fend.preview("12 * 12")
        #expect(!preview.isEmpty)
        #expect(preview.spans.count == 1)
        #expect(preview.spans[0].string == "144")
        #expect(preview.spans[0].isNumber)

        let incomplete = Fend.preview("12 * ")
        #expect(incomplete.isEmpty)
        #expect(incomplete.spans.isEmpty)
    }

    @Test("Span range integrity across full result string")
    func testSpanRanges() throws {
        let result = try Fend.evaluate("10 miles to km")
        #expect(!result.spans.isEmpty)

        // Concatenating span strings must equal full result string
        let concatenated = result.spans.map(\.string).joined()
        #expect(concatenated == result.string)

        // Verify each span's computed range extracts the exact span string
        for span in result.spans {
            guard let range = span.range else {
                Issue.record("Span \(span) has nil range")
                continue
            }
            #expect(result.string[range] == span.string)
        }
    }

    @Test("Syntactic categories coverage")
    func testSyntacticCategories() throws {
        let numResult = try Fend.evaluate("42")
        #expect(numResult.spans.contains { $0.isNumber })

        let boolResult = try Fend.evaluate("true")
        #expect(boolResult.spans.contains { $0.isBoolean })

        let strResult = try Fend.evaluate("\"hello\"")
        #expect(strResult.spans.contains { $0.isString })

        #expect(FendSpanKind.ident == .identifier)
    }

    @Test("FendResult RandomAccessCollection and protocol conformance")
    func testResultProtocols() throws {
        let result = try Fend.evaluate("1 + 1")

        // Collection indexing & count
        #expect(result.count == 1)
        #expect(result[0].string == "2")
        #expect(result.first?.string == "2")

        // CustomStringConvertible
        #expect("\(result)" == "2")
        #expect(result.description == "2")

        // LosslessStringConvertible / ExpressibleByStringLiteral
        let literalResult: FendResult = "hello"
        #expect(literalResult.string == "hello")
        #expect(literalResult.spans.count == 1)

        // Equality with String
        #expect(result == "2")
        #expect("2" == result)
        #expect(result != "3")

        // String operations
        #expect(result.contains("2"))
        #expect(result.hasPrefix("2"))
        #expect(result.hasSuffix("2"))
    }

    @Test("Codable serialization of Spans and Result")
    func testCodable() throws {
        let original = try Fend.evaluate("5 ft in meters")
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FendResult.self, from: data)

        #expect(decoded.string == original.string)
        #expect(decoded.isEmpty == original.isEmpty)
        #expect(decoded.spans.count == original.spans.count)
        for (a, b) in zip(decoded.spans, original.spans) {
            #expect(a.string == b.string)
            #expect(a.kind == b.kind)
        }
    }

    @Test("AttributedString conversion")
    func testAttributedString() throws {
        let result = try Fend.evaluate("5 ft in meters")
        let attributed = result.attributedString
        #expect(String(attributed.characters) == result.string)

        var foundNumber = false
        var foundIdentifier = false
        for run in attributed.runs {
            if let kind = run.fendSpanKind {
                if kind == .number { foundNumber = true }
                if kind == .identifier { foundIdentifier = true }
            }
        }
        #expect(foundNumber)
        #expect(foundIdentifier)
    }
}
