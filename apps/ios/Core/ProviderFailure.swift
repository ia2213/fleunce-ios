import Foundation

public enum ProviderFailureKind: String, Sendable {
    case authentication, modelAccess, quota, rateLimit, unavailable, invalidRequest, unknown
    public static func classify(status: Int, code: String?) -> Self {
        if status == 401 { return .authentication }
        if status == 403 || status == 404 { return .modelAccess }
        if status == 429 { return code == "insufficient_quota" ? .quota : .rateLimit }
        if status == 408 || status >= 500 { return .unavailable }
        if status == 400 || status == 422 { return .invalidRequest }
        return .unknown
    }
}

/// Keeps a provider's safe category and support reference, never its message or response body.
public struct ProviderFailure: LocalizedError, Sendable {
    public let status: Int
    public let code: String?
    public let message: String?
    public let reference: String?
    public var kind: ProviderFailureKind { .classify(status: status, code: code) }
    public init(status: Int, body: Data = Data(), reference: String? = nil) {
        self.status = status
        let json = body.count <= 16_384 ? (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] : nil
        let errorObj = json?["error"] as? [String: Any]
        self.code = Self.safeCode(errorObj?["code"] as? String ?? json?["code"] as? String)
        self.message = errorObj?["message"] as? String ?? json?["message"] as? String
        self.reference = Self.safeReference(reference)
    }
    public static func safeCode(_ value: String?) -> String? {
        guard let value, ["invalid_api_key", "insufficient_quota", "rate_limit_exceeded", "model_not_found", "permission_denied", "server_error"].contains(value) else { return nil }
        return value
    }
    public static func safeReference(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 128,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return value
    }
    public var errorDescription: String? {
        if let msg = message, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Groq Error (HTTP \(status)): \(msg)"
        }
        let fallback: String = switch kind {
        case .authentication: "Your Groq API key wasn’t accepted (HTTP 401). Check your key in Settings."
        case .modelAccess: "Groq model access error (HTTP \(status)). Check your model name or Groq permissions."
        case .quota: "Groq usage limit or quota reached."
        case .rateLimit: "Groq is rate-limiting requests. Please wait a moment."
        case .unavailable: "Groq service is temporarily unavailable."
        case .invalidRequest: "Groq rejected the request parameters."
        case .unknown: "Groq request failed (HTTP \(status))."
        }
        return reference.map { fallback + "\n\nReference: " + $0 } ?? fallback
    }
}
