import Foundation

/// Represents the result of evaluating an expression with Fend.
public struct FendCalculationResult: Equatable, Sendable {
    /// The formatted result text from fend-core.
    public let value: String

    /// Whether the expression evaluated to an empty result (e.g. whitespace, comment, or silent assignment).
    public let isEmpty: Bool

    public init(value: String, isEmpty: Bool = false) {
        self.value = value
        self.isEmpty = isEmpty
    }
}

/// Autocompletion suggestion from Fend.
public struct FendCompletion: Equatable, Sendable {
    /// The replacement start index within the prefix.
    public let startIndex: Int

    /// The suggested completion text to display.
    public let display: String

    public init(startIndex: Int, display: String) {
        self.startIndex = startIndex
        self.display = display
    }
}
