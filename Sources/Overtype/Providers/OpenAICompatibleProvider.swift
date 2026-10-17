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

    urlRequest.httpBody = try JSONSerialization.data(
      withJSONObject: Self.requestBody(
        model: request.model,
        systemPrompt: request.systemPrompt,
        userPrompt: userPrompt,
        temperature: request.temperature,
        reasoning: request.reasoning))

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
      // A 400 that names `temperature` or `reasoning_effort` in `error.param`
      // is classified so the engine can resend without it (specs/010, US3).
      if httpResponse.statusCode == 400,
        let parameter = Self.extractRejectedParameter(from: data)
      {
        throw ProviderError.parameterRejected(
          parameter, statusCode: 400, message: Self.extractErrorMessage(from: data))
      }
      // Surface the server's error message so distinct failures (401 bad key,
      // 429 rate limit, 500) are distinguishable instead of a generic string.
      throw ProviderError.apiError(
        statusCode: httpResponse.statusCode,
        message: Self.extractErrorMessage(from: data))
    }

    return try Self.parseResponseText(from: data)
  }

  /// Builds the chat-completions request body. Pure and `static` so the
  /// presence and absence of each optional key is unit-tested.
  ///
  /// `temperature` is sent only when the resolver produced one: current OpenAI
  /// reasoning models reject any non-default value with HTTP 400 unless
  /// reasoning effort is `none` (specs/010-model-aware-parameters, research R1),
  /// so "Automatic" must be able to leave it out entirely.
  ///
  /// `reasoning_effort` is sent only for a resolved level: older models and
  /// other OpenAI-compatible servers may reject the field, so a model without
  /// a profile gets it only when the action sets it. A thinking budget is a
  /// Gemini-only form and is never produced for this kind.
  static func requestBody(
    model: String, systemPrompt: String, userPrompt: String, temperature: Double?,
    reasoning: ReasoningSetting? = nil
  ) -> [String: Any] {
    var body: [String: Any] = [
      "model": model,
      "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": userPrompt],
      ],
    ]
    if let temperature {
      body["temperature"] = temperature
    }
    if case .level(let effort) = reasoning {
      body["reasoning_effort"] = effort
    }
    return body
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
    let finishReason = firstChoice["finish_reason"] as? String
    if finishReason == "content_filter" {
      throw ProviderError.responseBlocked(reason: "content filter")
    }
    // "length" means the output hit a token limit and the tail is missing;
    // returning it as success would write a truncated replacement over the
    // user's selection (009 review follow-up: the same silent-truncation class
    // H6 closes for Ollama prompts, on the output side).
    if finishReason == "length" {
      throw ProviderError.outputTruncated
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

  /// The optional parameter a 400 body names in `error.param`, if Overtype may
  /// drop it. Reads the structured field only, never the message text, which
  /// is fragile and can echo submitted text (specs/010 FR-016). If OpenAI
  /// omits `param` for a rejection, this returns nil and the fallback simply
  /// never fires (research R2). Pure logic, unit-tested.
  static func extractRejectedParameter(from data: Data) -> DroppableParameter? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let error = json["error"] as? [String: Any],
      let param = error["param"] as? String
    else { return nil }
    switch param {
    case "temperature":
      return .temperature
    case "reasoning_effort":
      return .reasoning
    default:
      return nil
    }
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
