import Foundation

/// Errors that can occur during Fend evaluation or context operations.
public enum FendError: LocalizedError, Equatable, Sendable {
    case evaluationFailed(String)
    case contextAllocationFailed
    case serializationFailed
    case deserializationFailed

    public var errorDescription: String? {
        switch self {
        case .evaluationFailed(let message):
            return message
        case .contextAllocationFailed:
            return "Failed to allocate fend calculation context"
        case .serializationFailed:
            return "Failed to serialize fend context variables"
        case .deserializationFailed:
            return "Failed to deserialize fend context variables"
        }
    }
}
