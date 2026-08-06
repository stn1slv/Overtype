import XCTest

@testable import Overtype

/// Covers `ProviderError.isRetryable`, which decides whether `ActionEngine`
/// makes a second provider call before showing an error.
final class ProviderErrorRetryTests: XCTestCase {

  // MARK: - Transient failures are retried

  func testTransientNetworkErrorsAreRetryable() {
    let transient: [URLError.Code] = [
      .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .cannotConnectToHost,
      .resourceUnavailable,
    ]
    for code in transient {
      XCTAssertTrue(
        ProviderError.networkError(URLError(code)).isRetryable,
        "expected URLError code \(code.rawValue) to be retryable")
    }
  }

  func testDeterministicNetworkErrorsAreNotRetryable() {
    // mapTransportError funnels every non-timeout URLError into .networkError,
    // so setup mistakes land here too. Retrying them costs the user a delay plus
    // a second doomed request before the real error appears.
    let deterministic: [URLError.Code] = [
      .badURL, .unsupportedURL, .cannotFindHost, .secureConnectionFailed,
      .serverCertificateUntrusted, .userAuthenticationRequired,
      .appTransportSecurityRequiresSecureConnection,
    ]
    for code in deterministic {
      XCTAssertFalse(
        ProviderError.networkError(URLError(code)).isRetryable,
        "expected URLError code \(code.rawValue) not to be retryable")
    }
  }

  func testUnclassifiableTransportErrorIsRetryable() {
    // mapTransportError wraps non-URLError failures in .networkError too. With
    // no code to inspect, allow the single retry rather than turning an unknown
    // blip into a hard error.
    struct OpaqueTransportError: Error {}
    XCTAssertTrue(ProviderError.networkError(OpaqueTransportError()).isRetryable)
  }

  func testMisconfiguredBaseURLIsNotRetried() {
    // End-to-end of the classification path a typo in baseURL actually takes.
    let mapped = ProviderError.mapTransportError(URLError(.cannotFindHost))
    XCTAssertFalse(mapped.isRetryable)
  }

  func testTimeoutIsRetryable() {
    XCTAssertTrue(ProviderError.timeout.isRetryable)
  }

  func testRateLimitIsRetryable() {
    XCTAssertTrue(ProviderError.apiError(statusCode: 429, message: "rate limited").isRetryable)
  }

  func testServerErrorsAreRetryable() {
    for statusCode in [500, 502, 503, 504, 599] {
      XCTAssertTrue(
        ProviderError.apiError(statusCode: statusCode, message: "server").isRetryable,
        "expected HTTP \(statusCode) to be retryable")
    }
  }

  // MARK: - Deterministic failures are not retried

  func testClientErrorsAreNotRetryable() {
    // A repeat of the identical request is rejected identically, so retrying
    // only delays the error. 429 is the deliberate exception, covered above.
    for statusCode in [400, 401, 403, 404, 422] {
      XCTAssertFalse(
        ProviderError.apiError(statusCode: statusCode, message: "client").isRetryable,
        "expected HTTP \(statusCode) not to be retryable")
    }
  }

  func testCancellationIsNeverRetryable() {
    // Escape is deliberate user intent; a retry would restart work the user
    // just stopped.
    XCTAssertFalse(ProviderError.cancelled.isRetryable)
  }

  func testConfigurationErrorsAreNotRetryable() {
    XCTAssertFalse(ProviderError.apiKeyMissing.isRetryable)
    XCTAssertFalse(ProviderError.invalidURL.isRetryable)
  }

  func testDeterministicResponseFailuresAreNotRetryable() {
    XCTAssertFalse(ProviderError.responseBlocked(reason: "SAFETY").isRetryable)
    XCTAssertFalse(ProviderError.emptyResponse.isRetryable)
    XCTAssertFalse(ProviderError.invalidResponse.isRetryable)
  }

  func testContextChangedIsNotRetryable() {
    XCTAssertFalse(ProviderError.contextChanged.isRetryable)
  }

  // MARK: - Log labels stay redaction-safe

  func testAPIErrorLogLabelOmitsServerMessage() {
    // The server body can echo fragments of the submitted text, so it must not
    // reach a warning-level log line (privacy principle).
    let secret = "the user's confidential selected text"
    let label = ProviderError.apiError(statusCode: 500, message: secret).logLabel
    XCTAssertEqual(label, "HTTP 500")
    XCTAssertFalse(label.contains(secret))
  }

  func testNetworkErrorLogLabelOmitsUnderlyingDescription() {
    let label = ProviderError.networkError(URLError(.notConnectedToInternet)).logLabel
    XCTAssertEqual(label, "network error")
  }
}
