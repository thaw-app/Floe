import CFendCore
import Foundation

/// An isolated evaluation context maintaining variables, custom units, and session history.
public final class FendContext: @unchecked Sendable {
    private var rawPointer: OpaquePointer?
    private let lock = NSLock()

    /// Initialize a new calculation context.
    public init() throws {
        guard let ptr = fend_context_new() else {
            throw FendError.contextAllocationFailed
        }
        self.rawPointer = ptr
    }

    deinit {
        if let ptr = rawPointer {
            fend_context_free(ptr)
        }
    }

    /// Reset all stored variables and settings in this context.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        guard let ptr = rawPointer else { return }
        fend_context_reset(ptr)
    }

    /// Gives the context its exchange rates, by currency code: how much of each one unit of the base currency buys,
    /// the base currency among them at 1. An empty table takes them away. Variables are kept.
    public func setExchangeRates(_ rates: [String: Double]) {
        lock.lock()
        defer { lock.unlock() }
        guard let ptr = rawPointer else { return }
        let codes = rates.keys.sorted()
        let values = codes.map { rates[$0] ?? 0 }
        let texts = codes.map { strdup($0) }
        defer { texts.forEach { free($0) } }
        let pointers = texts.map { UnsafePointer<CChar>($0) }
        fend_context_set_exchange_rates(ptr, pointers, values, codes.count)
    }

    /// Evaluate an expression and mutate context state (e.g. variable assignments).
    /// Returns the evaluation result containing the formatted text and syntactic spans.
    /// Throws `FendError.evaluationFailed` if the expression syntax or calculation is invalid.
    @discardableResult
    public func evaluate(_ query: String) throws -> FendResult {
        lock.lock()
        defer { lock.unlock() }
        guard let ptr = rawPointer else {
            throw FendError.contextAllocationFailed
        }

        guard let rawResult = fend_evaluate(ptr, query) else {
            throw FendError.evaluationFailed("Unknown evaluation error")
        }
        defer { fend_result_free(rawResult) }

        if fend_result_is_ok(rawResult) {
            return extractResult(from: rawResult)
        } else {
            let errorMsg = fend_result_get_error(rawResult).map { String(cString: $0) } ?? "Evaluation error"
            throw FendError.evaluationFailed(errorMsg)
        }
    }

    /// Evaluate an expression and return only the formatted result text.
    @_disfavoredOverload
    @discardableResult
    public func evaluate(_ query: String) throws -> String {
        let result: FendResult = try evaluate(query)
        return result.string
    }

    /// Evaluate an expression as a non-mutating preview.
    /// Does not alter context variables. If the expression is incomplete or invalid,
    /// returns an empty result instead of throwing.
    public func preview(_ query: String) -> FendResult {
        lock.lock()
        defer { lock.unlock() }
        guard let ptr = rawPointer else {
            return FendResult(string: "", spans: [], isEmpty: true)
        }

        guard let rawResult = fend_evaluate_preview(ptr, query) else {
            return FendResult(string: "", spans: [], isEmpty: true)
        }
        defer { fend_result_free(rawResult) }

        return extractResult(from: rawResult)
    }

    /// Evaluate an expression as a non-mutating preview returning only the formatted text.
    @_disfavoredOverload
    public func preview(_ query: String) -> String {
        let result: FendResult = preview(query)
        return result.string
    }

    /// Serialize variables stored in this context to binary data.
    public func serializeVariables() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let ptr = rawPointer else {
            throw FendError.contextAllocationFailed
        }

        let needed = fend_context_serialize_variables(ptr, nil, 0)
        guard needed >= 0 else {
            throw FendError.serializationFailed
        }
        if needed == 0 {
            return Data()
        }

        var data = Data(count: Int(needed))
        let written = data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Int64 in
            guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return fend_context_serialize_variables(ptr, baseAddress, buffer.count)
        }

        guard written >= 0 else {
            throw FendError.serializationFailed
        }
        return data
    }

    /// Restore variables previously serialized with `serializeVariables()`.
    public func deserializeVariables(from data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let ptr = rawPointer else {
            throw FendError.contextAllocationFailed
        }

        let status: Int32 = data.withUnsafeBytes { buffer in
            // Empty data has no address and holds no variables: it is refused, not taken as restored.
            guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return fend_context_deserialize_variables(ptr, baseAddress, buffer.count)
        }

        guard status == 0 else {
            throw FendError.deserializationFailed
        }
    }

    private func extractResult(from rawResult: OpaquePointer) -> FendResult {
        let fullString = fend_result_get_value(rawResult).map { String(cString: $0) } ?? ""
        let isEmpty = fend_result_is_empty(rawResult)
        let spanCount = fend_result_get_span_count(rawResult)

        var spans: [FendSpan] = []
        spans.reserveCapacity(spanCount)

        var currentIndex = fullString.startIndex
        for i in 0..<spanCount {
            guard let cStr = fend_result_get_span_string(rawResult, i) else { continue }
            let spanString = String(cString: cStr)
            let cKind = fend_result_get_span_kind(rawResult, i)
            let kind = FendSpan.Kind(cKind)

            let range: Range<String.Index>?
            if fullString[currentIndex...].hasPrefix(spanString),
               let nextIndex = fullString.index(currentIndex, offsetBy: spanString.count, limitedBy: fullString.endIndex) {
                range = currentIndex..<nextIndex
                currentIndex = nextIndex
            } else {
                range = nil
            }

            spans.append(FendSpan(string: spanString, kind: kind, range: range))
        }

        return FendResult(string: fullString, spans: spans, isEmpty: isEmpty)
    }
}
