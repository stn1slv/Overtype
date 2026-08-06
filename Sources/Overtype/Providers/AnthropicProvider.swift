import Foundation

/// Native Anthropic backend. Calls the Messages API (`POST /v1/messages`) and
/// maps Anthropic-specific outcomes (a declined response, an empty response) to
/// specific typed `ProviderError` values so no run fails silently.
///
/// The API key is read from the Keychain and sent in the `x-api-key` header; it
/// is never placed in the request URL (which could leak into logs).
public class AnthropicProvider: AIProvider {
  public let id: String
  private let config: ProviderConfig
  private let urlSession: URLSession

  /// Default base when the provider config sets no `baseURL`. Kept as a String
  /// (not a force-unwrapped `URL`) so the file has no `!`.
  private static let defaultBaseURLString = "https://api.anthropic.com/v1/"

  /// Wire-format version required on every request; a call without it is
  /// rejected. Pinned deliberately: this identifies the request/response schema,
  /// not a model, so pinning keeps a future server-side default from silently
  /// changing what we send.
  private static let anthropicVersion = "2023-06-01"

  /// `max_tokens` is required by this API and has no counterpart in
  /// `ProviderConfig` or `TransformRequest`, so it is a fixed value here rather
  /// than user configuration (see specs/007-anthropic-provider Clarifications).
  ///
  /// 8192 satisfies four constraints at once: far beyond any in-place rewrite of
  /// a selection; below the size at which a non-streaming request risks a
  /// transport timeout; enough headroom for models that spend part of the same
  /// budget on reasoning (this cap covers reasoning *and* answer text together);
  /// and within every current model's output ceiling.
  ///
  /// KNOWN RESIDUAL RISK, accepted deliberately: because this cap covers
  /// reasoning and answer text together, a reasoning-tier model working on a
  /// long selection can spend most of the budget reasoning and return a
  /// mid-sentence answer. `parseResponseText` treats a non-empty
  /// `stop_reason: "max_tokens"` as a success, so that truncated text is written
  /// over the user's selection with no error shown.
  ///
  /// Note this is NOT the same situation as `GeminiProvider`, whose equivalent
  /// comment justifies the same choice on the grounds that it "sends no
  /// maxOutputTokens, so this only occurs at the model's own default cap". This
  /// provider does set a cap, and sets it well below every model's ceiling, so
  /// truncation is reachable here where it is not there. The behaviour is kept
  /// for consistency with the other two providers and because the failure needs
  /// both a reasoning model and a long selection to bite; changing it to a typed
  /// error would diverge from OpenAI/Gemini and contradict the spec's stated
  /// edge-case handling, so it belongs in a spec revision rather than a silent
  /// change here.
  private static let maxTokens = 8192

  /// `stop_reason` values that mean the model finished normally. Anything else
  /// is reported as a block so the reason reaches the user specifically, rather
  /// than collapsing into a bare empty result. Mirrors GeminiProvider's
  /// treatment of any `finishReason` outside STOP / MAX_TOKENS.
  ///
  /// `max_tokens` is included deliberately: a length-truncated but non-empty
  /// response is a success and gets written, matching the other providers. If
  /// the truncated text is empty it falls through to `.emptyResponse`.
  private static let normalStopReasons: Set<String> = ["end_turn", "max_tokens", "stop_sequence"]

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
    urlRequest.addValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")

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
    urlRequest.addValue(apiKey, forHTTPHeaderField: "x-api-key")

    let userPrompt = request.userPromptTemplate.replacingOccurrences(
      of: "{{text}}", with: request.text)

    urlRequest.httpBody = try JSONSerialization.data(
      withJSONObject: Self.requestBody(
        model: request.model,
        systemPrompt: request.systemPrompt,
        userPrompt: userPrompt))

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: urlRequest)
    } catch {
      // Distinguish timeout/cancellation from other transport failures.
      throw ProviderError.mapTransportError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ProviderError.invalidResponse
    }

    if httpResponse.statusCode != 200 {
      // Reuse the OpenAI-style extraction: Anthropic's error body is also
      // `{ "error": { "message": ... } }`, so distinct failures (401 bad key,
      // 404 unknown model, 429 rate limit) stay distinguishable.
      //
      // No retry logic belongs here. `ProviderError.isRetryable` already returns
      // true for 408, 429, and 5xx-except-501, which covers Anthropic's 529
      // `overloaded_error` via the 500...599 range.
      throw ProviderError.apiError(
        statusCode: httpResponse.statusCode,
        message: OpenAICompatibleProvider.extractErrorMessage(from: data))
    }

    return try Self.parseResponseText(from: data)
  }

  /// Builds the Messages API request body. Pure and `static` so the omissions
  /// below are assertable in a unit test rather than guarded only by a comment.
  ///
  /// DELIBERATE OMISSION, do not "fix" without reading this: `temperature` is
  /// NOT sent, and this function takes no temperature argument so it cannot be.
  /// The Opus 4.7/4.8, Opus 5, Sonnet 5, and Fable 5 generation reject
  /// `temperature` (and `top_p` / `top_k`) with HTTP 400. Older models such as
  /// `claude-haiku-4-5` — currently the documented default — still accept them,
  /// so this is not "every model would fail today"; it is that the set of models
  /// which accept them shrinks with each release. Sending the value
  /// conditionally would mean a per-model allow-list that goes stale on every
  /// release and turns into a hard request-validation failure mid-run, so it is
  /// dropped for all Anthropic requests. The action-level setting still applies
  /// to the OpenAI and Gemini providers.
  ///
  /// For the same reason no `thinking` or `effort` field is sent either: the
  /// accepted values differ per model (some reject "disabled", others cap it by
  /// effort level). Each model's own default applies, `maxTokens` is sized to
  /// leave room for it, and `extractText` guarantees any reasoning content that
  /// does come back is never written to the user's document.
  static func requestBody(model: String, systemPrompt: String, userPrompt: String) -> [String: Any]
  {
    return [
      "model": model,
      "max_tokens": maxTokens,
      // `system` is a top-level field. A {"role": "system"} entry inside
      // `messages` is a validation error on this API.
      "system": systemPrompt,
      "messages": [["role": "user", "content": userPrompt]],
    ]
  }

  /// Builds `<base>messages`.
  ///
  /// Takes no model argument: unlike Gemini, Anthropic carries the model in the
  /// request body rather than the URL path, so there is a single fixed path and
  /// none of GeminiProvider's colon-escaping workaround is needed.
  static func endpointURL(base: URL?) throws -> URL {
    let baseString = base?.absoluteString ?? defaultBaseURLString
    let normalized = baseString.hasSuffix("/") ? baseString : baseString + "/"
    guard let url = URL(string: "\(normalized)messages") else {
      throw ProviderError.invalidURL
    }
    return url
  }

  /// Pure parsing + failure mapping for a 200 Messages body. Unit-tested.
  /// Returns the concatenated answer text, or throws a specific error.
  static func parseResponseText(from data: Data) throws -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ProviderError.invalidResponse
    }

    // Non-normal stop reasons are reported specifically. Guarded on the field
    // being present so a body without one falls through to extraction rather
    // than erroring.
    //
    // Checked BEFORE the `content` guard on purpose: a decline that produced no
    // output normally still carries `"content": []`, but a body that omits
    // `content` entirely would otherwise degrade to the generic
    // `.invalidResponse` and lose the reason the user needs to see.
    if let stopReason = json["stop_reason"] as? String,
      !normalStopReasons.contains(stopReason)
    {
      throw ProviderError.responseBlocked(reason: blockReason(stopReason, from: json))
    }

    guard let content = json["content"] as? [[String: Any]] else {
      throw ProviderError.invalidResponse
    }

    let text = extractText(from: content)
    if text.isEmpty {
      throw ProviderError.emptyResponse
    }
    return text
  }

  /// Builds the reported reason for a non-normal stop, enriched with the refusal
  /// category when the service supplies one (e.g. `refusal (cyber)`).
  ///
  /// The sibling `stop_details.explanation` is deliberately NOT used: it is
  /// server-authored prose that can echo fragments of the submitted text, and
  /// this reason is interpolated into `errorDescription`, which is shown to the
  /// user. `category` is a short fixed enum and is safe.
  static func blockReason(_ stopReason: String, from json: [String: Any]) -> String {
    guard let details = json["stop_details"] as? [String: Any],
      let category = details["category"] as? String,
      !category.isEmpty
    else {
      return stopReason
    }
    return "\(stopReason) (\(category))"
  }

  /// Concatenates the `text` of every content block whose `type` is exactly
  /// `"text"`, in order.
  ///
  /// This is an allow-list, not a deny-list, and that is load-bearing. Blocks of
  /// type `thinking` / `redacted_thinking` carry model reasoning, and reasoning
  /// is on by default on the Claude 5 tier — this provider sends no `thinking`
  /// field to suppress it, so responses can legitimately contain it. Writing it
  /// would silently replace the user's selection with model scratch work instead
  /// of failing visibly. Allow-listing means an unrecognised future block type
  /// is skipped rather than typed into the user's document.
  static func extractText(from content: [[String: Any]]) -> String {
    return
      content
      .filter { ($0["type"] as? String) == "text" }
      .compactMap { $0["text"] as? String }
      .joined()
  }
}
