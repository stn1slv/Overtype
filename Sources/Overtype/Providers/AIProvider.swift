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
  static let retryableURLErrorCodes: Set<URLError.Code> = [
    .networkConnectionLost,
    .notConnectedToInternet,
    .dnsLookupFailed,
    .cannotConnectToHost,
    .resourceUnavailable,
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
      // 429 (rate limited) and 5xx (server fault) are the retryable HTTP
      // outcomes. Other 4xx codes describe the request itself, so a repeat of
      // that same request is rejected identically.
      return statusCode == 429 || (500...599).contains(statusCode)
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
