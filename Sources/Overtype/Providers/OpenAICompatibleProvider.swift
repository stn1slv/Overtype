import Foundation

public class OpenAICompatibleProvider: AIProvider {
    public let id: String
    private let config: ProviderConfig
    private let urlSession: URLSession
    
    public init(config: ProviderConfig) {
        self.config = config
        self.id = config.id
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
        sessionConfig.timeoutIntervalForResource = config.timeoutSeconds
        self.urlSession = URLSession(configuration: sessionConfig)
    }
    
    public func transform(_ request: TransformRequest) async throws -> String {
        guard let baseURL = config.baseURL else {
            throw ProviderError.invalidURL
        }
        
        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Fetch API Key from Keychain if configured
        if let keychainKey = config.keychainKey {
            do {
                let apiKey = try KeychainStore.shared.retrieve(key: keychainKey)
                urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            } catch {
                throw ProviderError.apiKeyMissing
            }
        }
        
        let userPrompt = request.userPromptTemplate.replacingOccurrences(of: "{{text}}", with: request.text)
        
        let body: [String: Any] = [
            "model": request.model,
            "temperature": request.temperature,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw ProviderError.apiError(statusCode: httpResponse.statusCode, message: "Server returned error code")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderError.invalidResponse
        }
        
        return content
    }
}
