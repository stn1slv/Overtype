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
    let url = try Self.endpointURL(base: config.baseURL)
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
    } catch KeychainError.itemNotFound {
      throw ProviderError.apiKeyMissing
    } catch let error as ProviderError {
      throw error
    } catch {
      // A locked keychain or a denied ACL is not a missing key (finding H5).
      // The HUD still shows the missing-key message (the fix lives in the same
      // place either way), but the log names the real failure so the user is
      // not sent to re-enter a key that is stored fine. Key name and status
      // only, never a value (mirrors OllamaProvider.authorizationHeader).
      Logger.shared.log(
        "Keychain read failed for \"\(keychainKey)\"; treating as missing API key "
          + "(\(error.localizedDescription))",
        level: .warning)
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

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: urlRequest)
    } catch {
      // Typed mapping so Escape maps to a quiet cancel and a timeout to
      // ProviderError.timeout instead of a generic error HUD.
      throw ProviderError.mapTransportError(error)
    }

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

    return try Self.parseResponseText(from: data)
  }

  /// Builds `<base>/chat/completions`. The `openai` kind has no default base
  /// URL on purpose (unlike Gemini/Anthropic/Ollama): "OpenAI-compatible"
  /// names a protocol, not a host, so a nil base is a configuration error.
  static func endpointURL(base: URL?) throws -> URL {
    guard let base = base else {
      throw ProviderError.invalidURL
    }
    return base.appendingPathComponent("chat/completions")
  }

  /// Pure parsing + failure mapping for a 200 chat-completions body (finding
  /// H5). Unit-tested; contract:
  /// specs/009-stability-hardening/contracts/openai-response-handling.md.
  static func parseResponseText(from data: Data) throws -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = json["choices"] as? [[String: Any]],
      let firstChoice = choices.first,
      let message = firstChoice["message"] as? [String: Any]
    else {
      throw ProviderError.invalidResponse
    }

    // A refusal arrives as `message.refusal` alongside null content, and
    // filtered output as `finish_reason == "content_filter"`. Both map to the
    // typed blocked error with a short category, never the server's refusal
    // text: that text is server-authored and can echo the submitted prompt
    // (Principle V). Before this, a refusal degraded to the generic
    // "invalid response" and content-filter stops looked like normal output.
    if let refusal = message["refusal"] as? String, !refusal.isEmpty {
      throw ProviderError.responseBlocked(reason: "refusal")
    }
    if let finishReason = firstChoice["finish_reason"] as? String,
      finishReason == "content_filter"
    {
      throw ProviderError.responseBlocked(reason: "content filter")
    }

    guard let content = message["content"] as? String else {
      throw ProviderError.invalidResponse
    }

    // The `openai` kind points at arbitrary servers (LM Studio, vLLM,
    // DeepSeek-style deployments) whose models can inline reasoning markers in
    // `content` (finding H5); the shared stripper removes a leading block
    // exactly as the Ollama provider does. An empty or whitespace-only result
    // is the typed emptyResponse, not a success.
    let text = ReasoningStripper.stripLeadingBlock(content)
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProviderError.emptyResponse
    }
    return text
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
