import Foundation

public struct TransformRequest {
  public let text: String
  public let systemPrompt: String
  public let userPromptTemplate: String
  public let model: String
  public let temperature: Double

  public init(
    text: String, systemPrompt: String, userPromptTemplate: String, model: String,
    temperature: Double
  ) {
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
    }
  }

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
