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

        let result2 = try Fend.evaluate("2 * (3 + 4)")
        #expect(result2 == "14")

        let result3 = try Fend.evaluate("10 / 4")
        #expect(result3 == "2.5")
    }

    @Test("Unit and currency-style conversions")
    func testUnitConversions() throws {
        let length = try Fend.evaluate("5 ft in meters")
        #expect(length == "1.524 m")

        let temp = try Fend.evaluate("100 degC in degF")
        #expect(temp == "212 °F" || temp.contains("212"))

        let hex = try Fend.evaluate("0x20 to decimal")
        #expect(hex == "32")
    }

    @Test("Non-mutating preview")
    func testPreview() throws {
        let previewVal = Fend.preview("3 + 5")
        #expect(previewVal == "8")

        // Incomplete expression returns empty without crashing
        let incomplete = Fend.preview("3 + ")
        #expect(incomplete.isEmpty)
    }

    @Test("Context variable state and isolation")
    func testContextVariables() throws {
        let context = try FendContext()
        let assignResult = try context.evaluate("my_var = 50")
        #expect(assignResult.value == "50" || assignResult.isEmpty)

        let evalResult = try context.evaluate("my_var * 2")
        #expect(evalResult.value == "100")

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
}
