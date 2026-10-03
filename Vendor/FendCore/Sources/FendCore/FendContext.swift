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

    /// Evaluate an expression and mutate context state (e.g. variable assignments).
    /// Throws `FendError.evaluationFailed` if the expression syntax or calculation is invalid.
    public func evaluate(_ query: String) throws -> FendCalculationResult {
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
            let value = fend_result_get_value(rawResult).map { String(cString: $0) } ?? ""
            let isEmpty = fend_result_is_empty(rawResult)
            return FendCalculationResult(value: value, isEmpty: isEmpty)
        } else {
            let errorMsg = fend_result_get_error(rawResult).map { String(cString: $0) } ?? "Evaluation error"
            throw FendError.evaluationFailed(errorMsg)
        }
    }

    /// Evaluate an expression as a non-mutating preview.
    /// Does not alter context variables. If the expression is incomplete or invalid,
    /// returns an empty result instead of throwing.
    public func preview(_ query: String) -> FendCalculationResult {
        lock.lock()
        defer { lock.unlock() }
        guard let ptr = rawPointer else {
            return FendCalculationResult(value: "", isEmpty: true)
        }

        guard let rawResult = fend_evaluate_preview(ptr, query) else {
            return FendCalculationResult(value: "", isEmpty: true)
        }
        defer { fend_result_free(rawResult) }

        let value = fend_result_get_value(rawResult).map { String(cString: $0) } ?? ""
        let isEmpty = fend_result_is_empty(rawResult)
        return FendCalculationResult(value: value, isEmpty: isEmpty)
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
            guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return fend_context_deserialize_variables(ptr, baseAddress, buffer.count)
        }

        guard status == 0 else {
            throw FendError.deserializationFailed
        }
    }
}
