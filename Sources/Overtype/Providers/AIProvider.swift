import Foundation

public struct TransformRequest {
    public let text: String
    public let systemPrompt: String
    public let userPromptTemplate: String
    public let model: String
    public let temperature: Double

    public init(text: String, systemPrompt: String, userPromptTemplate: String, model: String, temperature: Double) {
        self.text = text
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
        self.model = model
        self.temperature = temperature
    }
}

public protocol AIProvider {
    var id: String { get }
    func transform(_ request: TransformRequest) async throws -> String
}

public enum ProviderError: Error, LocalizedError {
    case apiKeyMissing
    case invalidURL
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case timeout
    case cancelled
    case contextChanged

    public var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API Key is missing from the Keychain."
        case .invalidURL:
            return "The provider URL is invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let statusCode, let message):
            return "API Error \(statusCode): \(message)"
        case .invalidResponse:
            return "Received an invalid response from the AI provider."
        case .timeout:
            return "The request timed out."
        case .cancelled:
            return "The request was cancelled."
        case .contextChanged:
            return "The selection or active app changed before writing, so nothing was changed."
        }
    }
}
