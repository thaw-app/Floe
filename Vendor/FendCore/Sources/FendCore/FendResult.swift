import Foundation

/// Represents the result of evaluating an expression with Fend, exposing both
/// the full plain text representation and individual syntactic spans.
public struct FendResult: Equatable, Hashable, Sendable {
    public typealias Span = FendSpan

    /// The formatted result text from fend-core.
    public let string: String

    /// The list of syntactic spans comprising this result.
    public let spans: [Span]

    /// Whether the expression produced no visible output (e.g. whitespace, comment, or silent assignment).
    public let isEmpty: Bool

    public init(
        string: String,
        spans: [Span] = [],
        isEmpty: Bool = false
    ) {
        self.string = string
        self.spans = spans
        self.isEmpty = isEmpty
    }

    /// Convenience initializer using `value` for compatibility.
    public init(
        value: String,
        spans: [Span] = [],
        isEmpty: Bool = false
    ) {
        self.init(string: value, spans: spans, isEmpty: isEmpty)
    }

    /// Synonym for `string`.
    public var value: String { string }

    /// Synonym for `string`.
    public var text: String { string }
}

// MARK: - Backwards Compatibility Typealias

/// Alias for `FendResult` to maintain compatibility with existing usages.
public typealias FendCalculationResult = FendResult

// MARK: - Protocols Conformance

extension FendResult: CustomStringConvertible {
    public var description: String { string }
}

extension FendResult: CustomDebugStringConvertible {
    public var debugDescription: String {
        "FendResult(string: \(string.debugDescription), spans: \(spans), isEmpty: \(isEmpty))"
    }
}

extension FendResult: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let spans = value.isEmpty ? [] : [FendSpan(string: value, kind: .other)]
        self.init(string: value, spans: spans, isEmpty: value.isEmpty)
    }
}

extension FendResult: LosslessStringConvertible {
    public init(_ description: String) {
        self.init(stringLiteral: description)
    }
}

extension FendResult: RandomAccessCollection {
    public typealias Element = FendSpan
    public typealias Index = Int

    public var startIndex: Int { spans.startIndex }
    public var endIndex: Int { spans.endIndex }
    public subscript(position: Int) -> FendSpan { spans[position] }
}

// MARK: - String Equality and Operations

extension FendResult {
    public static func == (lhs: FendResult, rhs: String) -> Bool {
        lhs.string == rhs
    }

    public static func == (lhs: String, rhs: FendResult) -> Bool {
        lhs == rhs.string
    }

    /// Returns whether the result string contains the given substring.
    public func contains<S: StringProtocol>(_ other: S) -> Bool {
        string.contains(other)
    }

    /// Returns whether the result string starts with the given prefix.
    public func hasPrefix<S: StringProtocol>(_ prefix: S) -> Bool {
        string.hasPrefix(prefix)
    }

    /// Returns whether the result string ends with the given suffix.
    public func hasSuffix<S: StringProtocol>(_ suffix: S) -> Bool {
        string.hasSuffix(suffix)
    }
}

// MARK: - Codable

extension FendResult: Codable {}

// MARK: - AttributedString Support

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension FendResult {
    /// Formats the complete result into an `AttributedString` preserving each span's syntactic kind.
    public var attributedString: AttributedString {
        var attributed = AttributedString()
        for span in spans {
            attributed.append(span.attributedString)
        }
        return attributed
    }
}

// MARK: - FendCompletion

/// Autocompletion suggestion from Fend.
public struct FendCompletion: Equatable, Hashable, Sendable, Codable {
    /// The replacement start index within the prefix.
    public let startIndex: Int

    /// The suggested completion text to display.
    public let display: String

    public init(startIndex: Int, display: String) {
        self.startIndex = startIndex
        self.display = display
    }
}

extension FendCompletion: CustomStringConvertible {
    public var description: String { display }
}
