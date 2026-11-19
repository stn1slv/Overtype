import Foundation

public struct TransformRequest {
  public let text: String
  public let systemPrompt: String
  public let userPromptTemplate: String
  public let model: String
  /// `nil` means the request carries no temperature at all.
  public let temperature: Double?
  /// `nil` means the request carries no reasoning parameter at all.
  public let reasoning: ReasoningSetting?

  public init(
    text: String, systemPrompt: String, userPromptTemplate: String, model: String,
    temperature: Double?, reasoning: ReasoningSetting? = nil
  ) {
    self.text = text
    self.systemPrompt = systemPrompt
    self.userPromptTemplate = userPromptTemplate
    self.model = model
    self.temperature = temperature
    self.reasoning = reasoning
  }

  /// A copy without `parameter`, or `nil` when this request does not carry it
  /// (so the caller knows a rejection of it cannot be fixed by dropping it).
  public func removing(_ parameter: DroppableParameter) -> TransformRequest? {
    switch parameter {
    case .temperature:
      guard temperature != nil else { return nil }
      return TransformRequest(
        text: text, systemPrompt: systemPrompt, userPromptTemplate: userPromptTemplate,
        model: model, temperature: nil, reasoning: reasoning)
    case .reasoning:
      guard reasoning != nil else { return nil }
      return TransformRequest(
        text: text, systemPrompt: systemPrompt, userPromptTemplate: userPromptTemplate,
        model: model, temperature: temperature, reasoning: nil)
    }
  }
}

public protocol AIProvider {
  var id: String { get }
  func transform(_ request: TransformRequest) async throws -> String
}

/// Why Apple's on-device model cannot serve a request
/// (specs/011-apple-foundation-models). Plain Swift so it exists, and can be
/// tested, on every macOS version the app supports.
public enum OnDeviceModelUnavailability: Equatable {
  /// macOS is older than 27, the first version the provider supports.
  case operatingSystemTooOld
  case deviceNotEligible
  case appleIntelligenceNotEnabled
  /// The model is still downloading or otherwise not ready.
  case modelNotReady
  /// A reason added by a later macOS version.
  case unknown
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
  case responseBlocked(reason: String)
  case emptyResponse
  /// The provider's endpoint did not answer at all. Distinct from
  /// `.networkError` because a locally hosted backend that is simply not
  /// running is a setup problem the user fixes on their own machine, not a
  /// transient network condition (see specs/008-ollama-provider, R6).
  case serviceUnreachable(address: String)
  /// The service answered, but the requested model is not installed on it.
  case modelNotAvailable(model: String)
  /// The prompt is larger than the model's context window can hold together
  /// with a full answer. Thrown before the transformation request is built, so
  /// the selection is never sent (specs/008-ollama-provider FR-010b). The
  /// provider may already have asked the service about the model's window,
  /// which carries no user text.
  case inputTooLargeForContext(limit: Int)
  /// The provider cut its response short (e.g. `finish_reason == "length"`), so
  /// the tail of the replacement is missing. Writing it anyway would silently
  /// lose the end of the user's text, the same truncation class the Ollama
  /// prompt guard closes on the input side (009 review follow-up to H5).
  case outputTruncated
  /// The provider rejected one optional parameter by name (HTTP 400 with an
  /// OpenAI `error.param`). `ActionEngine.transformWithRetry` resends once
  /// without it; when it cannot, the error surfaces as a plain `apiError`
  /// (specs/010-model-aware-parameters, US3).
  case parameterRejected(DroppableParameter, statusCode: Int, message: String)
  /// Apple's on-device model cannot run on this Mac right now
  /// (specs/011-apple-foundation-models). Each reason has its own fix.
  case onDeviceModelUnavailable(OnDeviceModelUnavailability)
  /// The prompt plus the answer did not fit in the model's context window, in
  /// tokens. Distinct from `inputTooLargeForContext`, which counts bytes and is
  /// raised before sending: the on-device model also reaches this limit when
  /// its answer runs on too long (specs/011 research R7).
  case contextWindowExceeded(tokenLimit: Int)
  /// The model reported that it does not support the text's language.
  case unsupportedLanguage(code: String)
  /// The system limited how often Overtype may call the model. `resetDate`
  /// is when the limit ends, if the system said so.
  case rateLimited(resetDate: Date?)
  /// Any other failure of the on-device model, with Apple's own description.
  case onDeviceModelFailed(message: String)

  public var errorDescription: String? {
    switch self {
    case .onDeviceModelUnavailable(let reason):
      switch reason {
      case .operatingSystemTooOld:
        return "The Apple on-device model requires macOS 27 or later. Nothing was changed."
      case .deviceNotEligible:
        return
          "This Mac does not support Apple Intelligence, so the on-device model "
          + "cannot run. Nothing was changed."
      case .appleIntelligenceNotEnabled:
        return
          "Turn on Apple Intelligence in System Settings to use the on-device "
          + "model. Nothing was changed."
      case .modelNotReady:
        return
          "The on-device model is not ready yet (it may still be downloading). "
          + "Try again later. Nothing was changed."
      case .unknown:
        return "The on-device model is not available right now. Nothing was changed."
      }
    case .contextWindowExceeded(let tokenLimit):
      return
        "The text is too long for the on-device model: the selection, the "
        + "action's prompt and the answer must fit in \(tokenLimit) tokens together. "
        + "Select less text and try again. Nothing was changed."
    case .unsupportedLanguage(let code):
      return
        "The on-device model does not support this text's language (\(code)). "
        + "Nothing was changed."
    case .rateLimited:
      return
        "macOS temporarily limited how often Overtype can use the on-device "
        + "model. Wait a moment and try again. Nothing was changed."
    case .onDeviceModelFailed(let message):
      return "The on-device model failed (\(message)). Nothing was changed."
    case .parameterRejected(_, let statusCode, let message):
      return "API Error \(statusCode): \(message)"
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
    case .responseBlocked(let reason):
      return "The AI provider blocked the response (reason: \(reason)). Nothing was changed."
    case .emptyResponse:
      return "The AI provider returned no text to write. Nothing was changed."
    case .serviceUnreachable(let address):
      return
        "Could not reach the AI service at \(address). If it runs on this Mac, "
        + "check that it is started. Nothing was changed."
    case .modelNotAvailable(let model):
      return
        "The model \"\(model)\" is not installed on the AI service. Install it, "
        + "or choose a model that is. Nothing was changed."
    case .inputTooLargeForContext(let limit):
      // The unit is UTF-8 bytes, not characters, and saying "characters" would
      // mislead exactly the users the difference bites: a CJK selection costs
      // about three per character, so someone told "limit 1024 characters"
      // would keep failing at ~340 and have no idea why.
      //
      // Only "select less text" is actionable. Lowering the action's Max
      // Characters cannot make this run succeed — it makes the same selection
      // fail earlier, with a different message.
      return
        "The selection is too large for this provider (limit \(limit) bytes, "
        + "including the action's prompt; non-Latin text costs more than one "
        + "byte per character). Select less text and try again. Nothing was changed."
    case .outputTruncated:
      return
        "The AI provider cut its response short, so the replacement would be "
        + "incomplete. Select less text and try again. Nothing was changed."
    }
  }

  /// URLError codes that describe a transient condition, where the same request
  /// can plausibly succeed moments later. Everything else (bad URL, unknown
  /// host, TLS failure, authentication required) describes a setup problem that
  /// a second identical request cannot fix.
  ///
  /// Deliberate exclusion, do not "fix" without reading this: `.cannotFindHost`
  /// (-1003) is left out even though CFNetwork emits it for most DNS failures,
  /// including transient resolver hiccups. It is also what a typo in `baseURL`
  /// produces, and the two are indistinguishable from the code alone. The
  /// tradeoff is chosen against retrying, because a misconfigured provider is
  /// the more common cause and a user waiting on a doomed second request cannot
  /// tell why. A real connectivity outage still retries: it surfaces as
  /// `.notConnectedToInternet` or `.cannotConnectToHost`, both listed here.
  static let retryableURLErrorCodes: Set<URLError.Code> = [
    .networkConnectionLost,
    .notConnectedToInternet,
    .dnsLookupFailed,
    .cannotConnectToHost,
  ]

  /// Whether a single automatic retry is worth attempting.
  ///
  /// Only transient failures qualify: a dropped connection, a timeout, a rate
  /// limit, or a server-side fault can all succeed on a second identical call.
  /// Configuration errors (missing key, bad URL), deterministic refusals
  /// (safety block, empty result), malformed payloads, and user cancellation
  /// do not: retrying them fails the same way and only delays the error the
  /// user needs to see. Pure logic, unit-tested.
  public var isRetryable: Bool {
    switch self {
    case .timeout:
      return true
    case .networkError(let underlying):
      // `mapTransportError` funnels every non-timeout, non-cancelled URLError
      // into this case, including deterministic ones: a typo in baseURL surfaces
      // as .cannotFindHost, a TLS misconfiguration as .secureConnectionFailed.
      // Retrying those costs the user a delay plus a second doomed request, so
      // match on the code rather than blanket-retrying the case.
      guard let urlError = underlying as? URLError else {
        // A non-URLError transport failure cannot be classified, so allow the
        // single retry rather than turning an unknown blip into a hard error.
        return true
      }
      return Self.retryableURLErrorCodes.contains(urlError.code)
    case .apiError(let statusCode, _):
      // Retryable: 408 (some proxies return it instead of a socket timeout),
      // 429 (rate limited), and 5xx server faults except 501. Other 4xx codes
      // describe the request itself, so a repeat is rejected identically, and
      // 501 (Not Implemented) means the server will never serve this call.
      if statusCode == 408 || statusCode == 429 { return true }
      return (500...599).contains(statusCode) && statusCode != 501
    case .parameterRejected:
      // Handled by its own drop-and-resend branch in transformWithRetry: an
      // identical resend would be rejected identically.
      return false
    case .apiKeyMissing, .invalidURL, .invalidResponse, .cancelled, .contextChanged,
      .responseBlocked, .emptyResponse, .outputTruncated:
      // .outputTruncated: the same request produces the same token limit, so a
      // retry truncates identically and only delays the error.
      return false
    case .serviceUnreachable, .modelNotAvailable, .inputTooLargeForContext:
      // All three are permanent by construction. A service that is not running
      // will not have started within the retry pause, a model that is not
      // installed will not appear on a second identical request, and an
      // oversized selection is oversized twice. Note this is deliberately
      // stricter than `retryableURLErrorCodes`, which still treats
      // `.cannotConnectToHost` as transient: that entry is correct for a cloud
      // host and is left untouched, while the Ollama provider maps the same
      // condition onto `.serviceUnreachable` before it gets there.
      return false
    case .rateLimited(let resetDate):
      // Retry only when the limit ends soon. `ActionEngine` then waits until
      // the reset before the retry (`transientRetryPauseSeconds`); a later
      // reset would keep the user waiting, so the error is shown at once.
      guard let resetDate else { return true }
      return resetDate.timeIntervalSinceNow <= Self.maxUsefulRateLimitWait
    case .onDeviceModelUnavailable, .contextWindowExceeded, .unsupportedLanguage,
      .onDeviceModelFailed:
      // Device state, text length and language do not change between two
      // identical requests a moment apart (specs/011 FR-007).
      return false
    }
  }

  /// The longest wait for a rate limit to clear that still makes the single
  /// retry worthwhile. The pause before that retry lasts until the reset.
  static let maxUsefulRateLimitWait: TimeInterval = 5

  /// A redaction-safe label for logs. `errorDescription` may embed a server
  /// message, which can echo fragments of the submitted text, so it must not
  /// reach `info`+ logs (Principle: privacy).
  public var logLabel: String {
    switch self {
    case .timeout:
      return "timeout"
    case .networkError:
      return "network error"
    case .apiError(let statusCode, _):
      return "HTTP \(statusCode)"
    case .parameterRejected(let parameter, let statusCode, _):
      return "HTTP \(statusCode) (rejected parameter: \(parameter.rawValue))"
    case .apiKeyMissing:
      return "missing API key"
    case .invalidURL:
      return "invalid URL"
    case .invalidResponse:
      return "invalid response"
    case .cancelled:
      return "cancelled"
    case .contextChanged:
      return "context changed"
    case .responseBlocked:
      return "response blocked"
    case .emptyResponse:
      return "empty response"
    // Payload-free on purpose: the address, the model name, and the limit are
    // all safe to show the user, but a log label carries no payload at all so
    // this convention cannot drift into leaking one later.
    case .serviceUnreachable:
      return "service unreachable"
    case .modelNotAvailable:
      return "model not available"
    case .inputTooLargeForContext:
      return "input too large for context"
    case .outputTruncated:
      return "output truncated"
    case .onDeviceModelUnavailable:
      return "on-device model unavailable"
    case .contextWindowExceeded:
      return "context window exceeded"
    case .unsupportedLanguage:
      return "unsupported language"
    case .rateLimited:
      return "rate limited"
    case .onDeviceModelFailed:
      return "on-device model failed"
    }
  }

  /// Maps a transport-layer failure from `URLSession` to a typed provider error,
  /// so every provider distinguishes cancellation (Escape) and timeout from
  /// other network failures the same way. Pure logic, unit-tested.
  public static func mapTransportError(_ error: Error) -> ProviderError {
    // Escape/Task cancellation before the request resolves surfaces as a
    // structured-concurrency CancellationError; map it to the clean no-op.
    if error is CancellationError {
      return .cancelled
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .timedOut:
        return .timeout
      case .cancelled:
        return .cancelled
      default:
        return .networkError(urlError)
      }
    }
    return .networkError(error)
  }
}
