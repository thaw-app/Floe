import CFendCore
import Foundation

/// Main entry point for interacting with the `fend-core` calculation engine.
public enum Fend {
    /// Returns the underlying fend-core library version.
    public static var version: String {
        String(cString: fend_get_version())
    }

    /// Shared global context for lightweight one-off calculations.
    private static let sharedContext: FendContext = {
        do {
            return try FendContext()
        } catch {
            fatalError("Failed to initialize default FendContext: \(error)")
        }
    }()

    /// Evaluate an expression using the shared context.
    /// Returns the formatted result text on success, or throws `FendError`.
    @discardableResult
    public static func evaluate(_ query: String) throws -> String {
        let result = try sharedContext.evaluate(query)
        return result.value
    }

    /// Evaluate an expression as a non-mutating preview.
    /// Returns the formatted preview string, or empty string if incomplete/invalid.
    public static func preview(_ query: String) -> String {
        sharedContext.preview(query).value
    }

    /// Get autocompletions for a given input prefix.
    public static func completions(for prefix: String) -> [FendCompletion] {
        guard let raw = fend_get_completions(prefix) else {
            return []
        }
        defer { fend_completions_free(raw) }

        let count = fend_completions_get_count(raw)
        let startIndex = Int(fend_completions_get_start_index(raw))
        var results: [FendCompletion] = []
        results.reserveCapacity(count)

        for i in 0..<count {
            if let item = fend_completions_get_item(raw, i) {
                results.append(FendCompletion(startIndex: startIndex, display: String(cString: item)))
            }
        }
        return results
    }
}
