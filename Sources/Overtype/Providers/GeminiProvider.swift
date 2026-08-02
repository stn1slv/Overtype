import Foundation

/// Native Google Gemini backend. Calls the `generateContent` REST endpoint and
/// maps Gemini-specific outcomes (safety blocks, empty candidates) to specific
/// typed `ProviderError` values so no run fails silently.
///
/// The API key is read from the Keychain and sent in the `x-goog-api-key`
/// header; it is never placed in the request URL (which could leak into logs).
public class GeminiProvider: AIProvider {
  public let id: String
  private let config: ProviderConfig
  private let urlSession: URLSession

  /// Default base when the provider config sets no `baseURL`. Kept as a String
  /// (not a force-unwrapped `URL`) so the file has no `!`.
  private static let defaultBaseURLString = "https://generativelanguage.googleapis.com/v1beta/"

  public init(config: ProviderConfig) {
    self.config = config
    self.id = config.id

    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
    sessionConfig.timeoutIntervalForResource = config.timeoutSeconds
    self.urlSession = URLSession(configuration: sessionConfig)
  }

  public func transform(_ request: TransformRequest) async throws -> String {
    let url = try Self.endpointURL(base: config.baseURL, model: request.model)

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

    // API key: Keychain only, sent as a header (never in the URL).
    guard let keychainKey = config.keychainKey, !keychainKey.isEmpty else {
      throw ProviderError.apiKeyMissing
    }
    let apiKey: String
    do {
      apiKey = try KeychainStore.shared.retrieve(key: keychainKey)
    } catch {
      throw ProviderError.apiKeyMissing
    }
    guard !apiKey.isEmpty else { throw ProviderError.apiKeyMissing }
    urlRequest.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

    let userPrompt = request.userPromptTemplate.replacingOccurrences(
      of: "{{text}}", with: request.text)

    let body: [String: Any] = [
      "systemInstruction": ["parts": [["text": request.systemPrompt]]],
      "contents": [["role": "user", "parts": [["text": userPrompt]]]],
      "generationConfig": ["temperature": request.temperature],
    ]
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: urlRequest)
    } catch is CancellationError {
      // Escape/Task cancellation before the request resolves surfaces as a
      // structured-concurrency CancellationError; map it to the clean no-op.
      throw ProviderError.cancelled
    } catch let error as URLError {
      // Distinguish timeout/cancellation from other transport failures (FR-006).
      switch error.code {
      case .timedOut:
        throw ProviderError.timeout
      case .cancelled:
        throw ProviderError.cancelled
      default:
        throw ProviderError.networkError(error)
      }
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ProviderError.invalidResponse
    }

    if httpResponse.statusCode != 200 {
      // Reuse the OpenAI-style extraction: Gemini's error body is also
      // `{ "error": { "message": ... } }`, so distinct failures (400 bad key,
      // 404 unknown model, 429 quota) stay distinguishable.
      throw ProviderError.apiError(
        statusCode: httpResponse.statusCode,
        message: OpenAICompatibleProvider.extractErrorMessage(from: data))
    }

    return try Self.parseResponseText(from: data)
  }

  /// Builds `<base>models/<model>:generateContent`. Constructed by string so the
  /// `:generateContent` action suffix is not percent-encoded (as
  /// `appendingPathComponent` would do to the colon).
  static func endpointURL(base: URL?, model: String) throws -> URL {
    let baseString = base?.absoluteString ?? defaultBaseURLString
    let normalized = baseString.hasSuffix("/") ? baseString : baseString + "/"
    guard let url = URL(string: "\(normalized)models/\(model):generateContent") else {
      throw ProviderError.invalidURL
    }
    return url
  }

  /// Pure parsing + failure mapping for a 200 `generateContent` body. Unit-tested.
  /// Returns the concatenated candidate text, or throws a specific error.
  static func parseResponseText(from data: Data) throws -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ProviderError.invalidResponse
    }

    // Prompt-level block: no candidates are produced.
    if let feedback = json["promptFeedback"] as? [String: Any],
      let blockReason = feedback["blockReason"] as? String
    {
      throw ProviderError.responseBlocked(reason: blockReason)
    }

    guard let candidates = json["candidates"] as? [[String: Any]],
      let firstCandidate = candidates.first
    else {
      // No candidates and no explicit block reason: still a block, unknown reason.
      throw ProviderError.responseBlocked(reason: "no candidates returned")
    }

    // Candidate-level block: any finish reason other than a normal completion
    // (STOP / MAX_TOKENS) means the model stopped for a reason like SAFETY,
    // RECITATION, BLOCKLIST, or PROHIBITED_CONTENT. Treat all of them as blocked
    // so the reason is reported specifically (FR-006), not as a bare empty result.
    if let finishReason = firstCandidate["finishReason"] as? String,
      finishReason != "STOP", finishReason != "MAX_TOKENS"
    {
      throw ProviderError.responseBlocked(reason: finishReason)
    }

    // A MAX_TOKENS finish with non-empty text is deliberately treated as a
    // success: the partial (possibly truncated) output is sanitized and written
    // like any other result, matching OpenAICompatibleProvider's behavior. No
    // maxOutputTokens is sent, so this only occurs at the model's own default
    // cap. If the truncated text is empty it falls through to .emptyResponse.
    let text = extractText(from: firstCandidate)
    if text.isEmpty {
      throw ProviderError.emptyResponse
    }
    return text
  }

  /// Concatenates the `text` of every part in a candidate's content, in order.
  static func extractText(from candidate: [String: Any]) -> String {
    guard let content = candidate["content"] as? [String: Any],
      let parts = content["parts"] as? [[String: Any]]
    else {
      return ""
    }
    return parts.compactMap { $0["text"] as? String }.joined()
  }
}
