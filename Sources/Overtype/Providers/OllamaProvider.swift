import Foundation

/// Backend for a locally hosted Ollama service. Calls Ollama's own chat API
/// (`POST /api/chat`) rather than its OpenAI-compatible surface, because only
/// the native endpoint reports model reasoning in a field separate from the
/// answer and returns error text specific enough to tell "the service is not
/// running" apart from "that model was never downloaded"
/// (see specs/008-ollama-provider, clarification 1).
///
/// Unlike the three cloud providers, this one requires no credential: the
/// service normally listens on the user's own machine. A credential is sent
/// only when the user actually stored one, for a remote or proxied deployment.
public class OllamaProvider: AIProvider {
  public let id: String
  private let config: ProviderConfig
  private let urlSession: URLSession

  /// Default base when the provider config sets no `baseURL`. Kept as a String
  /// (not a force-unwrapped `URL`) so the file has no `!`, matching
  /// `GeminiProvider` and `AnthropicProvider`.
  private static let defaultBaseURLString = "http://localhost:11434"

  /// Context window requested on every call, in tokens.
  ///
  /// LOAD-BEARING, do not remove to "let the model decide": when a prompt does
  /// not fit the context window, Ollama drops the oldest part of it and answers
  /// anyway, with no error. The model would then rewrite only the tail of the
  /// selection while `TextWriter` replaces all of it — a silent loss of the
  /// user's text, which Principle II exists to prevent.
  ///
  /// CRITICAL: this window covers the prompt **and** the answer together, not
  /// the prompt alone. An in-place rewrite is by nature about as long as its
  /// input, so the window must fit roughly twice the input, and it must do so
  /// for the worst-case script, not for English.
  ///
  /// Sizing, worked out against `maxSafeInputCharacters` (6000):
  ///   - worst case is a script that tokenises at about 1 token per character
  ///     (Chinese, Japanese, Korean), so 6000 characters of input is up to
  ///     ~6000 tokens, not the ~2200 an English estimate would suggest;
  ///   - a same-length rewrite needs about the same again: ~6000;
  ///   - the system prompt adds a few hundred.
  /// That is ~12200 tokens worst case, which 16384 covers with margin. English
  /// prose uses roughly a third of it, leaving ample room for a model that
  /// reasons before answering.
  ///
  /// ACCEPTED TRADEOFF: this also caps models whose own window is larger and
  /// raises it for models trained on a shorter one. Raising costs KV-cache
  /// memory (a few hundred MB at this size for the small models this provider
  /// targets) and can degrade a model trained at 2048. Both beat silent
  /// truncation of the user's text.
  ///
  /// KNOWN RESIDUAL RISK, accepted deliberately, mirroring the equivalent note
  /// on `AnthropicProvider.maxTokens`: because this budget is shared between
  /// the answer and any reasoning the model emits, a reasoning-heavy model
  /// working on a maximum-length CJK selection could still hit the boundary. It
  /// would stop with `done_reason: "length"`, and `parseResponseText` treats a
  /// non-empty truncated answer as success, so it is written. That matches what
  /// the other three providers do with a length-truncated response and what the
  /// spec's edge-case section calls for; changing it to a typed error would
  /// diverge from them and belongs in a spec revision, not a silent change here.
  static let contextWindowTokens = 16384

  /// Largest selection this provider will send, in characters.
  ///
  /// `contextWindowTokens` covers the *default* action cap, but
  /// `maxInputCharacters` is user-adjustable up to 20000, so the window alone
  /// is not a guarantee. This constant closes that hole: a selection above it is
  /// refused before anything is sent (FR-010b).
  ///
  /// Derivation, deliberately done at ~1 token per CHARACTER rather than at an
  /// English prose ratio: `text.count` counts Characters, and the check has no
  /// idea what script it is looking at. A ratio taken from English (~2.7
  /// characters per token) is wrong by roughly 3x for Chinese, Japanese and
  /// Korean, and being wrong in that direction is precisely the failure this
  /// constant exists to prevent — the prompt would be silently shortened by the
  /// service and a partial rewrite would replace the whole selection.
  ///
  /// So: 6000 characters is at most ~6000 tokens of prompt, needs ~6000 more
  /// for a same-length rewrite, plus a few hundred for the system prompt, and
  /// `contextWindowTokens` (16384) covers that. 6000 also sits comfortably above
  /// the 5000-character default action cap, so an ordinary selection is never
  /// refused; only a user who raised that cap can reach this bound.
  ///
  /// Erring LOW is the safe direction and is why this is a fixed constant rather
  /// than a per-request estimate: a low bound refuses slightly early and
  /// visibly, a high one lets the service shorten the user's text silently.
  static let maxSafeInputCharacters = 6000

  public init(config: ProviderConfig) {
    self.config = config
    self.id = config.id

    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
    sessionConfig.timeoutIntervalForResource = config.timeoutSeconds
    self.urlSession = URLSession(configuration: sessionConfig)
  }

  public func transform(_ request: TransformRequest) async throws -> String {
    let userPrompt = request.userPromptTemplate.replacingOccurrences(
      of: "{{text}}", with: request.text)

    // First, before a URL, a body, or the Keychain is touched: an oversized
    // request costs nothing and reaches nothing.
    //
    // Measured on what is actually SENT, not on `request.text`. Two ways the
    // selection alone understates the prompt: `replacingOccurrences` substitutes
    // every `{{text}}`, so a template naming it twice doubles the input, and the
    // system prompt is user-editable and uncapped. Checking the selection would
    // let either exceed the window while the guard stayed silent.
    try Self.checkInputSize(systemPrompt: request.systemPrompt, userPrompt: userPrompt)

    let url = try Self.endpointURL(base: config.baseURL)

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

    // DELIBERATE ABSENCE, do not "fix" by copying AnthropicProvider's
    // `guard let keychainKey ... else { throw .apiKeyMissing }`: an Ollama
    // provider legitimately has no credential. Worse, key *presence* does not
    // imply a credential exists — `SettingsViewModel.saveProvider` assigns
    // `keychainKey = "overtype-<slug>-key"` to every provider it creates but
    // writes the Keychain entry only `if !apiKey.isEmpty`. A provider added
    // through Settings with an empty key field therefore carries a keychainKey
    // pointing at nothing, and guarding on it would fail every normal local run
    // with "API Key is missing from the Keychain" (FR-005, research R8).
    if let header = Self.authorizationHeader(forKeychainKey: config.keychainKey) {
      urlRequest.addValue(header, forHTTPHeaderField: "Authorization")
    }

    urlRequest.httpBody = try JSONSerialization.data(
      withJSONObject: Self.requestBody(
        model: request.model,
        systemPrompt: request.systemPrompt,
        userPrompt: userPrompt,
        temperature: request.temperature))

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: urlRequest)
    } catch {
      // The only place any provider overrides the shared transport mapping.
      // Confined here on purpose: for a cloud host a refused connection can be
      // transient and `ProviderError.retryableURLErrorCodes` rightly retries it,
      // but for a service on this machine it means "not running", which a retry
      // cannot fix and which the user must be told about by name (research R6).
      throw Self.mapTransportFailure(error, address: Self.displayAddress(for: url))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ProviderError.invalidResponse
    }

    if httpResponse.statusCode != 200 {
      if Self.isModelNotFound(status: httpResponse.statusCode, body: data) {
        // Carries the model WE asked for, never a name parsed out of the
        // server's message: server-authored text can echo the request and must
        // not reach an error the user sees (Principle V).
        throw ProviderError.modelNotAvailable(model: request.model)
      }
      throw ProviderError.apiError(
        statusCode: httpResponse.statusCode,
        message: Self.extractErrorMessage(from: data))
    }

    return try Self.parseResponseText(from: data)
  }

  /// The address to name in `.serviceUnreachable`.
  ///
  /// Includes the port when there is one: the whole point of this error is to
  /// tell the user which address failed, and someone running the service on a
  /// non-default port learns nothing from a bare "localhost". Falls back to the
  /// full URL string if there is no host to extract. Pure logic, unit-tested.
  static func displayAddress(for url: URL) -> String {
    guard let host = url.host else { return url.absoluteString }
    guard let port = url.port else { return host }
    return "\(host):\(port)"
  }

  /// Refuses a request whose prompt exceeds `maxSafeInputCharacters` (FR-010b).
  ///
  /// Takes the composed prompt rather than the raw selection, because the
  /// selection is not what reaches the model: the action's template may repeat
  /// `{{text}}`, and the system prompt is user-editable. Pure logic,
  /// unit-tested.
  static func checkInputSize(systemPrompt: String, userPrompt: String) throws {
    if systemPrompt.count + userPrompt.count > maxSafeInputCharacters {
      throw ProviderError.inputTooLargeForContext(limit: maxSafeInputCharacters)
    }
  }

  /// Builds the `Authorization` header value, or nil when the provider has no
  /// usable credential. A missing `keychainKey`, an absent Keychain entry, a
  /// Keychain error, and an empty stored value are all "no credential" rather
  /// than failures — see the comment in `transform`. Pure enough to unit-test
  /// through the value it returns.
  /// A read failure is distinguished from an absent entry rather than collapsed
  /// into one `try?`. Both still mean "send no credential", because a local
  /// service needs none, but only one of them is normal: a locked keychain or a
  /// denied ACL on a provider the user *did* give a key to would otherwise
  /// surface as a bare "API Error 401" with nothing pointing at the Keychain.
  /// The key name and the OSStatus are not secrets, so they may be logged; the
  /// value never is.
  static func authorizationHeader(forKeychainKey keychainKey: String?) -> String? {
    guard let keychainKey = keychainKey, !keychainKey.isEmpty else { return nil }

    let apiKey: String
    do {
      apiKey = try KeychainStore.shared.retrieve(key: keychainKey)
    } catch KeychainError.itemNotFound {
      // The ordinary keyless case, including a provider created in Settings
      // with an empty key field. Not worth a log line.
      return nil
    } catch {
      Logger.shared.log(
        "Keychain read failed for \"\(keychainKey)\"; continuing without a credential.",
        level: .warning)
      return nil
    }

    return apiKey.isEmpty ? nil : "Bearer \(apiKey)"
  }

  /// Builds `<base>/api/chat`.
  static func endpointURL(base: URL?) throws -> URL {
    let baseString = base?.absoluteString ?? defaultBaseURLString
    let normalized = baseString.hasSuffix("/") ? baseString : baseString + "/"
    guard let url = URL(string: "\(normalized)api/chat") else {
      throw ProviderError.invalidURL
    }
    return url
  }

  /// Builds the chat request body. Pure and `static` so the choices below are
  /// assertable in a unit test rather than guarded only by a comment.
  ///
  /// `stream: false` is LOAD-BEARING. This endpoint streams by default, and a
  /// streamed response is newline-delimited JSON objects rather than one
  /// document: parsing would fail, and a partial answer could be written over
  /// the user's selection (FR-010).
  ///
  /// `temperature` IS sent here, which is the opposite of `AnthropicProvider`.
  /// That is deliberate, not an oversight to be harmonised: Anthropic omits it
  /// because its newer models reject the field outright with HTTP 400, whereas
  /// Ollama applies `options` itself as generation parameters before the model
  /// sees them, so every model accepts it. No per-model allow-list risk exists
  /// here, so the action's setting is honoured (research R4).
  ///
  /// Fields NOT sent, each for a recorded reason: `think` (models that do not
  /// support it reject the whole request — the same trap feature 007 hit with
  /// Anthropic's `temperature`); `keep_alive` (how long a model stays resident
  /// is the service's policy and the user's setting, not ours); `num_predict`
  /// (no output cap, matching `GeminiProvider`); `tools` / `format` (text in,
  /// text out only). `OllamaProviderTests` asserts the exact key set so none of
  /// these can reappear by accident.
  static func requestBody(
    model: String, systemPrompt: String, userPrompt: String, temperature: Double
  ) -> [String: Any] {
    return [
      "model": model,
      "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": userPrompt],
      ],
      "stream": false,
      "options": [
        "temperature": temperature,
        "num_ctx": contextWindowTokens,
      ],
    ]
  }

  /// Pure parsing + failure mapping for a 200 chat body. Unit-tested.
  ///
  /// Reads `message.content` and nothing else. `message.thinking` carries model
  /// reasoning and is never read — this is an allow-list, not a deny-list, so a
  /// future sibling field is ignored by default rather than typed into the
  /// user's document (FR-009 layer 1). Mirrors
  /// `AnthropicProvider.extractText`, which filters to `text` blocks for the
  /// same reason.
  static func parseResponseText(from data: Data) throws -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let message = json["message"] as? [String: Any],
      let content = message["content"] as? String
    else {
      throw ProviderError.invalidResponse
    }

    // Verify, rather than assume, that the prompt reached the model whole.
    //
    // Everything else in this provider's size handling is preventive: it sends
    // `num_ctx` and refuses an oversized request up front. Both rely on the
    // service honouring the window, and if it does not, the truncation is
    // silent by definition — which is the one failure this feature was built to
    // avoid. `prompt_eval_count` is the only observable signal available: a
    // prompt clipped to the window reports a count at the window. Discarding an
    // answer that was produced from a truncated prompt costs the user a
    // visible error; writing it costs them part of their text.
    if let promptTokens = json["prompt_eval_count"] as? Int,
      promptTokens >= contextWindowTokens
    {
      throw ProviderError.inputTooLargeForContext(limit: maxSafeInputCharacters)
    }

    let text = stripLeadingReasoningBlock(content)
    if text.isEmpty {
      throw ProviderError.emptyResponse
    }
    return text
  }

  /// Removes a reasoning block from the START of the answer text.
  ///
  /// FR-009 layer 2, and scoped to this provider on purpose: `ResponseSanitizer`
  /// is shared by all four backends and is deliberately not touched. Models
  /// served by Ollama vary — some report reasoning in `message.thinking`, which
  /// layer 1 already excludes, but others wrap it in markers inside the answer
  /// itself, where layer 1 cannot see it.
  ///
  /// Only a block at the very start is removed. Reasoning is emitted before the
  /// answer, so that is where it occurs, and the narrow rule cannot swallow a
  /// legitimate `<think>` in the middle of text the user asked Overtype to
  /// rewrite. An opening marker with no closing match yields an empty string,
  /// which `parseResponseText` turns into `.emptyResponse`: failing visibly
  /// beats writing model scratch work into the document.
  /// Strips every *consecutive* leading block, not just the first: a model that
  /// emits two reasoning blocks back to back would otherwise leave the second
  /// one in the user's document, which is the exact failure this guards
  /// against. The loop terminates because each pass removes a non-empty prefix.
  static func stripLeadingReasoningBlock(_ text: String) -> String {
    var current = text.trimmingCharacters(in: .whitespacesAndNewlines)

    var strippedOne = true
    while strippedOne {
      strippedOne = false

      for tag in ["think", "thinking"] {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard current.lowercased().hasPrefix(open) else { continue }

        guard let closeRange = current.range(of: close, options: .caseInsensitive) else {
          // Unterminated: everything that follows is reasoning.
          return ""
        }
        current = String(current[closeRange.upperBound...])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        strippedOne = true
        break
      }
    }

    return stripOrphanReasoningPrefix(current)
  }

  /// Removes reasoning that has a CLOSING marker but no opening one.
  ///
  /// This shape is not hypothetical and is arguably the more common of the two.
  /// DeepSeek-R1's chat template appends `<think>` to the *prompt*, so the
  /// completion begins with bare reasoning and ends with a lone `</think>`:
  ///
  ///     "Okay, the subject is singular...\n</think>\nThe cat is sleeping."
  ///
  /// Layer 1 usually catches it, because Ollama splits such models' output into
  /// `message.thinking`. But that split depends on the served model declaring
  /// the thinking capability, and a custom Modelfile or a community GGUF may not
  /// — in which case the raw completion arrives in `content` and, without this
  /// rule, model scratch work would be typed over the user's selection.
  ///
  /// ACCEPTED TRADEOFF, do not "simplify" without reading this: text a user
  /// legitimately selected could contain a closing marker with its opening tag
  /// outside the selection (someone editing prose *about* this markup). That
  /// text would be cut. The rule is deliberately narrowed to make this as rare
  /// as possible — it fires only when NO opening marker precedes the closing
  /// one, so a properly paired block anywhere in the text is left alone — and
  /// the trade was made toward cutting rare prose over writing model reasoning
  /// into a document, because reasoning leakage is silent and unbounded while
  /// this is visible in the result.
  static func stripOrphanReasoningPrefix(_ text: String) -> String {
    for tag in ["think", "thinking"] {
      let open = "<\(tag)>"
      let close = "</\(tag)>"

      guard let closeRange = text.range(of: close, options: .caseInsensitive) else { continue }

      // A matched pair is not the orphan shape; leave it to the caller's rules.
      if let openRange = text.range(of: open, options: .caseInsensitive),
        openRange.lowerBound < closeRange.lowerBound
      {
        continue
      }

      return String(text[closeRange.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return text
  }

  /// Best-effort extraction of Ollama's `{ "error": "<string>" }` body.
  ///
  /// Note the shape differs from OpenAI's `{ "error": { "message": ... } }`, so
  /// the shared extractor alone would miss every Ollama error and show a raw
  /// JSON blob. It is still used as the fallback, which also brings its
  /// truncated-raw-body safety net. Pure logic, unit-tested.
  static func extractErrorMessage(from data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let message = json["error"] as? String,
      !message.isEmpty
    {
      return message
    }
    return OpenAICompatibleProvider.extractErrorMessage(from: data)
  }

  /// Whether a non-200 response means "that model is not installed here".
  /// Ollama answers 404 with `model '<name>' not found` (the wording varies by
  /// version; 0.32.5 omits the documented "try pulling it first" suffix, which
  /// is why this matches on the phrase rather than the full sentence).
  ///
  /// The JSON check is load-bearing, not defensive noise: this provider
  /// supports a remote endpoint, and a proxy in front of one answers a bad path
  /// with an HTML `404 Not Found` page. Matching the extracted text alone would
  /// read that as "the model is not installed" and send the user to fix the
  /// wrong thing — and permanently, since the error is non-retryable. Requiring
  /// Ollama's own `{"error": "<string>"}` shape keeps a routing failure an
  /// `.apiError`. Pure logic, unit-tested.
  static func isModelNotFound(status: Int, body: Data) -> Bool {
    guard status == 404 else { return false }
    guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let message = json["error"] as? String
    else {
      return false
    }
    return message.lowercased().contains("not found")
  }

  /// Maps a transport failure, turning "nothing answered at this address" into
  /// the specific `.serviceUnreachable` and delegating everything else — so
  /// timeout and cancellation keep exactly the meaning they have for every
  /// other provider. Pure logic, unit-tested.
  /// Only codes that mean "nothing answered at this address" qualify.
  /// `.networkConnectionLost` is deliberately NOT among them, and must not be
  /// added: it means the connection was established and then dropped, which
  /// proves the service *was* reachable and running. Treating it as
  /// `.serviceUnreachable` would make a transient blip permanent, skip the one
  /// automatic retry every other provider gets, and tell the user to start a
  /// service that is already started. It falls through to the shared mapping,
  /// which classifies it as retryable.
  static func mapTransportFailure(_ error: Error, address: String) -> ProviderError {
    if let urlError = error as? URLError {
      switch urlError.code {
      case .cannotConnectToHost, .cannotFindHost:
        return .serviceUnreachable(address: address)
      default:
        break
      }
    }
    return ProviderError.mapTransportError(error)
  }
}
