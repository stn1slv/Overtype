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
  /// Sizing, worked out against `maxSafePromptTokens` (6000):
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

  /// Largest prompt this provider will send, in estimated tokens.
  ///
  /// `contextWindowTokens` covers the *default* action cap, but
  /// `maxInputCharacters` is user-adjustable up to 20000, so the window alone
  /// is not a guarantee. This constant closes that hole: a prompt above it is
  /// refused before anything is sent (FR-010b).
  ///
  /// Derivation, deliberately done at ~1 token per unit rather than at an
  /// English prose ratio: a ratio taken from English (~2.7 characters per token)
  /// is wrong by roughly 3x for Chinese, Japanese and Korean, and being wrong in
  /// that direction is precisely the failure this constant exists to prevent —
  /// the prompt would be silently shortened by the service and a partial rewrite
  /// would replace the whole selection.
  ///
  /// So: 6000 estimated tokens of prompt needs ~6000 more for a same-length
  /// rewrite, and `contextWindowTokens` (16384) covers that with margin. For
  /// Latin and CJK text an estimated token is one character, so 6000 also sits
  /// above the 5000-character default action cap and an ordinary selection is
  /// never refused — though the system prompt counts toward the same budget, so
  /// an action with a very long system prompt narrows what is left for the
  /// selection.
  ///
  /// Erring LOW is the safe direction and is why this is a fixed constant rather
  /// than a per-request estimate: a low bound refuses slightly early and
  /// visibly, a high one lets the service shorten the user's text silently.
  static let maxSafePromptTokens = 6000

  /// Conservative upper bound on the tokens a string will occupy.
  ///
  /// `String.count` counts grapheme clusters, and a cluster can hold arbitrarily
  /// many scalars: `"👨‍👩‍👧‍👦".count` is 1 but the cluster is 25 UTF-8 bytes, and one
  /// Devanagari or Vietnamese cluster is routinely 6-12. Counting clusters
  /// would therefore let a 6000-"character" Hindi selection carry tens of
  /// thousands of tokens straight past the guard — the opposite of the
  /// conservative direction this bound is supposed to err in.
  ///
  /// The estimate is the UTF-8 byte count: a byte-level BPE token covers at
  /// least one byte, so the text itself can never cost more tokens than it has
  /// bytes.
  ///
  /// It is NOT a bound on the whole request. The server also prepends chat
  /// template and special tokens that never appear in this string — measured at
  /// roughly +30 on Ollama 0.32.5 (300 bytes of CJK reported 328 evaluated
  /// tokens; 1200 bytes reported 1194). `templateOverheadTokens` reserves room
  /// for that, and is why the budget sits below half the window rather than at
  /// it.
  ///
  /// MEASURED, not assumed (2026-08-06, Ollama 0.32.5 / tinyllama). An earlier
  /// version of this used `max(count, utf8.count / 3)` on the theory that
  /// multi-byte scripts average three-plus bytes per token. That is true for
  /// *common* characters, and false where the tokenizer falls back to bytes:
  /// 100 randomly chosen CJK characters (300 bytes) were reported by the server
  /// as **328 tokens** — about one token per byte. The old estimate would have
  /// called that 100, understating it by 3x, in the direction that loses the
  /// user's text.
  ///
  /// Consequence, stated plainly because it is user-visible: the budget is
  /// effectively in bytes, so it allows roughly 6000 Latin characters but only
  /// about 2000 CJK ones. That asymmetry is real rather than an artefact — those
  /// characters genuinely cost that much — and the README says so.
  static func estimatedTokens(_ text: String) -> Int {
    return text.utf8.count
  }

  /// Reserved for the chat template and special tokens the server adds and
  /// `estimatedTokens` cannot see. Measured at ~30; 128 leaves margin, and the
  /// margin is what separates a legitimate near-budget prompt from a truncated
  /// one in `truncationThreshold(grantedWindow:)`.
  static let templateOverheadTokens = 128

  /// Window assumed when the service will not tell us the real one.
  ///
  /// FAIL CLOSED, deliberately. An earlier version fell back to
  /// `maxSafePromptTokens` here, which re-created the very hole the granted
  /// window exists to close: a deployment that does not expose `/api/show` (a
  /// reverse proxy routing only `/api/chat`, say) got a 6000-token budget
  /// regardless of a model window of 2048, and the overflow was truncated in
  /// silence. 4096 is Ollama's own default when a model does not specify one,
  /// so assuming it is conservative without being punitive; the cost is that
  /// such deployments are limited to ~1920 bytes of prompt until `/api/show`
  /// becomes reachable.
  static let assumedWindowWhenUnknown = 4096

  /// Effective context window per model, as reported by the service.
  ///
  /// `contextWindowTokens` is what we ASK for; it is not necessarily what we
  /// get. Ollama clamps `num_ctx` down to a model's own trained maximum, so a
  /// model built at 4096 silently runs at 4096 no matter what we send — and a
  /// truncation check written against the requested value would then never fire
  /// for exactly the models most likely to truncate. Looked up once per model
  /// and cached; the lock is here because `ProviderRegistry` hands the same
  /// instance to every run.
  private var effectiveWindowCache: [String: Int] = [:]
  private let cacheLock = NSLock()

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

    // Resolved before the request so an oversized prompt is refused rather than
    // silently clipped by the server. Cached per model, so only the first run
    // pays the extra round trip.
    let granted = await grantedContextWindow(model: request.model)
    // The lookup swallows its own errors, including cancellation, so Escape
    // pressed during it is honoured here rather than silently continuing into
    // the chat request.
    try Task.checkCancellation()

    let budget = Self.promptBudget(grantedWindow: granted)
    let truncationAt = Self.truncationThreshold(grantedWindow: granted)

    // Before a URL, a body, or the Keychain is touched: an oversized
    // request costs nothing and reaches nothing.
    //
    // Measured on what is actually SENT, not on `request.text`. Two ways the
    // selection alone understates the prompt: `replacingOccurrences` substitutes
    // every `{{text}}`, so a template naming it twice doubles the input, and the
    // system prompt is user-editable and uncapped. Checking the selection would
    // let either exceed the window while the guard stayed silent.
    try Self.checkInputSize(
      systemPrompt: request.systemPrompt, userPrompt: userPrompt, budgetTokens: budget)

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

    return try Self.parseResponseText(
      from: data, truncationThreshold: truncationAt, reportedLimit: budget)
  }

  /// The window the service will actually use for this model, or nil if it
  /// could not be established.
  ///
  /// Sends only the model name — no selection, no prompt — to the same endpoint
  /// the transformation goes to, so it contacts no new host (FR-018). A failure
  /// here is never fatal: the caller falls back to the requested window, which
  /// is what the check did before this lookup existed.
  private func grantedContextWindow(model: String) async -> Int? {
    cacheLock.lock()
    let cached = effectiveWindowCache[model]
    cacheLock.unlock()
    if let cached { return cached }

    guard let url = try? Self.showEndpointURL(base: config.baseURL) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    // Bounded independently of the provider's timeout. The session's timeout
    // applies per task, so without this a deployment that never answers
    // `/api/show` would add a full `timeoutSeconds` to every run — and, since a
    // timeout is retryable, up to four times it across a retried run.
    request.timeoutInterval = min(Self.showRequestTimeoutSeconds, config.timeoutSeconds)
    if let header = Self.authorizationHeader(forKeychainKey: config.keychainKey) {
      request.addValue(header, forHTTPHeaderField: "Authorization")
    }
    guard let body = try? JSONSerialization.data(withJSONObject: ["model": model]) else {
      return nil
    }
    request.httpBody = body

    guard let (data, response) = try? await urlSession.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let window = Self.parseContextLength(from: data)
    else {
      return nil
    }

    cacheLock.lock()
    effectiveWindowCache[model] = window
    cacheLock.unlock()
    return window
  }

  /// Upper bound on the window lookup, independent of the provider timeout.
  static let showRequestTimeoutSeconds: Double = 5

  /// Builds `<base>/api/show`.
  static func showEndpointURL(base: URL?) throws -> URL {
    let baseString = base?.absoluteString ?? defaultBaseURLString
    let normalized = baseString.hasSuffix("/") ? baseString : baseString + "/"
    guard let url = URL(string: "\(normalized)api/show") else {
      throw ProviderError.invalidURL
    }
    return url
  }

  /// Reads the context length out of an `/api/show` body.
  ///
  /// The key is architecture-prefixed (`llama.context_length`,
  /// `qwen2.context_length`, …), so it is matched by suffix rather than by a
  /// list of architectures that would go stale. Pure logic, unit-tested.
  static func parseContextLength(from data: Data) -> Int? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let info = json["model_info"] as? [String: Any]
    else {
      return nil
    }
    // Take the SMALLEST positive match rather than the first: dictionary order
    // is unspecified, and a multimodal body can carry more than one
    // `*.context_length` (a vision tower exposes its own). First-match-wins
    // would pick a different window on different launches and then cache it for
    // the process lifetime. The smallest is also the safe one to believe.
    let lengths = info.compactMap { key, value -> Int? in
      guard key.hasSuffix(".context_length"), let length = value as? Int, length > 0 else {
        return nil
      }
      return length
    }
    return lengths.min()
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

  /// Refuses a request whose prompt exceeds `maxSafePromptTokens` (FR-010b).
  ///
  /// Takes the composed prompt rather than the raw selection, because the
  /// selection is not what reaches the model: the action's template may repeat
  /// `{{text}}`, and the system prompt is user-editable. Pure logic,
  /// unit-tested.
  static func checkInputSize(
    systemPrompt: String, userPrompt: String, budgetTokens: Int = maxSafePromptTokens
  ) throws {
    let promptTokens = estimatedTokens(systemPrompt) + estimatedTokens(userPrompt)
    if promptTokens > budgetTokens {
      throw ProviderError.inputTooLargeForContext(limit: budgetTokens)
    }
  }

  /// The prompt budget for a model, given the window the service granted it.
  ///
  /// MEASURED, not assumed (2026-08-06, Ollama 0.32.5 / tinyllama, whose window
  /// is 2048): when a prompt exceeds the window, the server does not error — it
  /// keeps roughly HALF the window and answers from that. Prompts of 800, 1200,
  /// 2000 and 4000 characters all came back reporting exactly 1026 evaluated
  /// tokens, while 400 characters reported 1194 untouched. So the usable prompt
  /// budget is half the window, and the other half is what the answer is
  /// generated into — which is also what an in-place rewrite needs.
  ///
  /// This is why the fixed `maxSafePromptTokens` alone was not enough: on a
  /// model whose window is below 12000, half of it is less than that constant,
  /// and the difference was silently truncated.
  /// Reserves TWICE the template overhead, which is not redundancy: the budget
  /// has to leave a strict gap below the truncation signal, and subtracting the
  /// overhead only once closes it exactly. With one reserve, a worst-case
  /// legitimate prompt evaluates to `budget + overhead == window / 2`, which is
  /// the signal itself, so it would be reported as truncated. A unit test
  /// (`testALegitimatePromptCanNeverReachTheTruncationSignal`) pins the gap.
  static func promptBudget(grantedWindow: Int?) -> Int {
    let window = grantedWindow ?? assumedWindowWhenUnknown
    return min(maxSafePromptTokens, max(1, window / 2 - templateOverheadTokens * 2))
  }

  /// The evaluated-token count at or above which the prompt must have been
  /// truncated.
  ///
  /// The two ranges have to be kept apart, and that is the whole reason
  /// `promptBudget` subtracts the overhead. A prompt that passed the pre-send
  /// check is at most `budget` bytes, so it can evaluate to at most
  /// `budget + overhead = window/2 - overhead + overhead`, i.e. strictly below
  /// half the window. A truncated prompt, measured, comes back AT half the
  /// window (1026 against a 2048-window model). So `>= window/2` means
  /// truncation and nothing else.
  ///
  /// Without the reserve these overlap: budget and signal would both be
  /// `window/2`, so a legitimate CJK prompt at the limit would be misreported as
  /// truncated, and a truncation landing a token low would be missed.
  static func truncationThreshold(grantedWindow: Int?) -> Int {
    let window = grantedWindow ?? assumedWindowWhenUnknown
    return max(1, window / 2)
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
  static func parseResponseText(
    from data: Data,
    truncationThreshold: Int = contextWindowTokens,
    reportedLimit: Int = maxSafePromptTokens
  ) throws -> String {
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
    //
    // `windowTokens` is the window the service GRANTED, not the one we asked
    // for. Comparing against the request would make this check dead for every
    // model whose own maximum is below `contextWindowTokens`, because Ollama
    // clamps `num_ctx` down to it — and those are precisely the models that
    // truncate.
    if let promptTokens = json["prompt_eval_count"] as? Int,
      promptTokens >= truncationThreshold
    {
      // Reports the budget actually in force, not the fixed constant: on a
      // small-window model the two differ, and naming 6000 when the run was
      // refused at 896 tells the user to aim at the wrong number.
      throw ProviderError.inputTooLargeForContext(limit: reportedLimit)
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
