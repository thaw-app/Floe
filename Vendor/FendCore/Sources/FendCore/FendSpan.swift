import CFendCore
import Foundation

/// The syntactic or semantic category of a styled text span in a Fend calculation result.
public enum FendSpanKind: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case number
    case builtInFunction
    case keyword
    case string
    case date
    case whitespace
    case identifier
    case boolean
    case other

    /// Convenience alias for `identifier`.
    public static let ident: FendSpanKind = .identifier

    /// Initialize a `FendSpanKind` from the underlying C enum value.
    init(_ cKind: CFendCore.FendSpanKind) {
        switch cKind {
        case FEND_SPAN_NUMBER: self = .number
        case FEND_SPAN_BUILT_IN_FUNCTION: self = .builtInFunction
        case FEND_SPAN_KEYWORD: self = .keyword
        case FEND_SPAN_STRING: self = .string
        case FEND_SPAN_DATE: self = .date
        case FEND_SPAN_WHITESPACE: self = .whitespace
        case FEND_SPAN_IDENT: self = .identifier
        case FEND_SPAN_BOOLEAN: self = .boolean
        case FEND_SPAN_OTHER: self = .other
        default: self = .other
        }
    }
}

/// Represents an individual syntax-highlighted text span within an evaluation result.
public struct FendSpan: Equatable, Hashable, Sendable {
    public typealias Kind = FendSpanKind

    /// The string text represented by this span.
    public let string: String

    /// The syntactic category of this span.
    public let kind: Kind

    /// The character range of this span within the parent result string, if available.
    public let range: Range<String.Index>?

    public init(
        string: String,
        kind: Kind,
        range: Range<String.Index>? = nil
    ) {
        self.string = string
        self.kind = kind
        self.range = range
    }

    /// Convenience alias for `string`.
    public var text: String { string }

    // MARK: - Category Check Predicates

    public var isNumber: Bool { kind == .number }
    public var isBuiltInFunction: Bool { kind == .builtInFunction }
    public var isKeyword: Bool { kind == .keyword }
    public var isString: Bool { kind == .string }
    public var isDate: Bool { kind == .date }
    public var isWhitespace: Bool { kind == .whitespace }
    public var isIdentifier: Bool { kind == .identifier }
    public var isBoolean: Bool { kind == .boolean }
    public var isOther: Bool { kind == .other }
}

extension FendSpan: CustomStringConvertible {
    public var description: String { string }
}

extension FendSpan: CustomDebugStringConvertible {
    public var debugDescription: String {
        "Span(\(string.debugDescription), kind: .\(kind.rawValue))"
    }
}

extension FendSpan: Codable {
    private enum CodingKeys: String, CodingKey {
        case string
        case kind
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(string, forKey: .string)
        try container.encode(kind, forKey: .kind)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let string = try container.decode(String.self, forKey: .string)
        let kind = try container.decode(Kind.self, forKey: .kind)
        self.init(string: string, kind: kind)
    }
}

// MARK: - AttributedString Support

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public enum FendSpanKindAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
    public typealias Value = FendSpanKind
    public static let name = "fendSpanKind"
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension AttributeScopes {
    struct FendAttributes: AttributeScope {
        public let fendSpanKind: FendSpanKindAttribute
    }

    var fend: FendAttributes.Type { FendAttributes.self }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.FendAttributes, T>) -> T {
        self[T.self]
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension FendSpan {
    /// Returns this span as an `AttributedString` attributed with `fendSpanKind`.
    public var attributedString: AttributedString {
        var attributed = AttributedString(string)
        attributed.fendSpanKind = kind
        return attributed
    }
}
