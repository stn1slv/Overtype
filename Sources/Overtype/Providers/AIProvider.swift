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
      .responseBlocked, .emptyResponse:
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
