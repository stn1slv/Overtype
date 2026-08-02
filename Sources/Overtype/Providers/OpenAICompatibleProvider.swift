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

    // Fetch API Key from Keychain
    guard let keychainKey = config.keychainKey, !keychainKey.isEmpty else {
      throw ProviderError.apiKeyMissing
    }

    do {
      let apiKey = try KeychainStore.shared.retrieve(key: keychainKey)
      guard !apiKey.isEmpty else {
        throw ProviderError.apiKeyMissing
      }
      urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    } catch {
      throw ProviderError.apiKeyMissing
    }

    let userPrompt = request.userPromptTemplate.replacingOccurrences(
      of: "{{text}}", with: request.text)

    let body: [String: Any] = [
      "model": request.model,
      "temperature": request.temperature,
      "messages": [
        ["role": "system", "content": request.systemPrompt],
        ["role": "user", "content": userPrompt],
      ],
    ]

    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await urlSession.data(for: urlRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ProviderError.invalidResponse
    }

    if httpResponse.statusCode != 200 {
      // Surface the server's error message so distinct failures (401 bad key,
      // 429 rate limit, 500) are distinguishable instead of a generic string.
      throw ProviderError.apiError(
        statusCode: httpResponse.statusCode,
        message: Self.extractErrorMessage(from: data))
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = json["choices"] as? [[String: Any]],
      let firstChoice = choices.first,
      let message = firstChoice["message"] as? [String: Any],
      let content = message["content"] as? String
    else {
      throw ProviderError.invalidResponse
    }

    return content
  }

  /// Best-effort extraction of an OpenAI-style `{ "error": { "message": ... } }`
  /// body, falling back to a truncated raw body. Pure logic, unit-tested.
  static func extractErrorMessage(from data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let error = json["error"] as? [String: Any],
      let message = error["message"] as? String,
      !message.isEmpty
    {
      return message
    }

    guard
      let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !raw.isEmpty
    else {
      return "Server returned an error with no readable body."
    }

    let maxLength = 200
    if raw.count > maxLength {
      return String(raw.prefix(maxLength)) + "…"
    }
    return raw
  }
}
