import XCTest

@testable import Overtype

/// Covers `ActionEngine.transformWithRetry`, the retry behavior itself rather
/// than just its classification helpers: that exactly one retry happens (never
/// two), that a non-retryable failure costs no second request, and that
/// cancellation prevents the retry.
///
/// No system boundary is involved: the function takes an injected `AIProvider`,
/// a delay, and a progress closure, so a counting fake drives it directly.
final class TransformRetryTests: XCTestCase {

  // MARK: - Fake provider

  /// Returns scripted outcomes in order, counting calls. `@unchecked Sendable`
  /// is safe here: each test drives it from a single task, never concurrently.
  private final class ScriptedProvider: AIProvider, @unchecked Sendable {
    let id = "fake"
    private(set) var callCount = 0
    private let outcomes: [Result<String, Error>]
    /// When set, the first call spins until the surrounding task is cancelled,
    /// so cancellation is deterministically pending at the retry decision.
    let awaitCancellationOnFirstCall: Bool

    init(_ outcomes: [Result<String, Error>], awaitCancellationOnFirstCall: Bool = false) {
      self.outcomes = outcomes
      self.awaitCancellationOnFirstCall = awaitCancellationOnFirstCall
    }

    func transform(_ request: TransformRequest) async throws -> String {
      callCount += 1
      if awaitCancellationOnFirstCall && callCount == 1 {
        while !Task.isCancelled {
          await Task.yield()
        }
      }
      guard callCount <= outcomes.count else {
        XCTFail("provider called \(callCount) times, only \(outcomes.count) outcomes scripted")
        return ""
      }
      return try outcomes[callCount - 1].get()
    }
  }

  private let request = TransformRequest(
    text: "hello", systemPrompt: "sys", userPromptTemplate: "{{text}}", model: "m",
    temperature: 0.0)

  /// Zero delay keeps the tests fast; the delay itself is covered by
  /// `RetryDelayClampTests`.
  private func run(
    _ provider: ScriptedProvider, delay: Double = 0, progress: @escaping (String) -> Void = { _ in }
  ) async throws -> String {
    try await ActionEngine.transformWithRetry(
      provider: provider, request: request, retryDelaySeconds: delay, showProgress: progress)
  }

  // MARK: - Happy path

  func testSuccessOnFirstAttemptMakesOneCall() async throws {
    let provider = ScriptedProvider([.success("clean text")])
    let result = try await run(provider)
    XCTAssertEqual(result, "clean text")
    XCTAssertEqual(provider.callCount, 1)
  }

  func testSuccessOnFirstAttemptShowsNoRetryProgress() async throws {
    let provider = ScriptedProvider([.success("ok")])
    var messages: [String] = []
    _ = try await run(provider, progress: { messages.append($0) })
    XCTAssertTrue(messages.isEmpty, "unexpected progress updates: \(messages)")
  }

  // MARK: - Retryable failures

  func testRetryableFailureThenSuccessReturnsSecondResult() async throws {
    let provider = ScriptedProvider([.failure(ProviderError.timeout), .success("second attempt")])
    let result = try await run(provider)
    XCTAssertEqual(result, "second attempt")
    XCTAssertEqual(provider.callCount, 2)
  }

  func testRetryShowsRetryingInTheHUD() async throws {
    let provider = ScriptedProvider([.failure(ProviderError.timeout), .success("ok")])
    var messages: [String] = []
    _ = try await run(provider, progress: { messages.append($0) })
    XCTAssertEqual(messages, ["Retrying..."])
  }

  func testRetriesExactlyOnceNeverTwice() async {
    // Both attempts fail retryably. The second error must propagate rather than
    // triggering a third call.
    let provider = ScriptedProvider([
      .failure(ProviderError.timeout),
      .failure(ProviderError.apiError(statusCode: 503, message: "unavailable")),
    ])
    do {
      _ = try await run(provider)
      XCTFail("expected the second failure to propagate")
    } catch let error as ProviderError {
      guard case .apiError(503, _) = error else {
        return XCTFail("expected the second error (503), got \(error)")
      }
    } catch {
      XCTFail("expected ProviderError, got \(error)")
    }
    XCTAssertEqual(provider.callCount, 2, "retry must happen exactly once")
  }

  func testRateLimitIsRetried() async throws {
    let provider = ScriptedProvider([
      .failure(ProviderError.apiError(statusCode: 429, message: "slow down")),
      .success("ok"),
    ])
    _ = try await run(provider)
    XCTAssertEqual(provider.callCount, 2)
  }

  // MARK: - Non-retryable failures

  func testNonRetryableFailurePropagatesWithoutSecondCall() async {
    let provider = ScriptedProvider([.failure(ProviderError.apiKeyMissing), .success("unreached")])
    do {
      _ = try await run(provider)
      XCTFail("expected apiKeyMissing to propagate")
    } catch let error as ProviderError {
      guard case .apiKeyMissing = error else {
        return XCTFail("expected apiKeyMissing, got \(error)")
      }
    } catch {
      XCTFail("expected ProviderError, got \(error)")
    }
    XCTAssertEqual(provider.callCount, 1, "a non-retryable failure must not be retried")
  }

  func testNonRetryableFailureShowsNoRetryProgress() async {
    let provider = ScriptedProvider([.failure(ProviderError.responseBlocked(reason: "SAFETY"))])
    var messages: [String] = []
    _ = try? await run(provider, progress: { messages.append($0) })
    XCTAssertTrue(messages.isEmpty, "a non-retryable failure must not announce a retry")
  }

  func testClientErrorIsNotRetried() async {
    let provider = ScriptedProvider([
      .failure(ProviderError.apiError(statusCode: 401, message: "unauthorized"))
    ])
    _ = try? await run(provider)
    XCTAssertEqual(provider.callCount, 1)
  }

  func testNonProviderErrorIsNotRetried() async {
    // Only ProviderError is classified; anything else propagates untouched.
    struct OtherError: Error {}
    let provider = ScriptedProvider([.failure(OtherError()), .success("unreached")])
    do {
      _ = try await run(provider)
      XCTFail("expected OtherError to propagate")
    } catch is OtherError {
      // expected
    } catch {
      XCTFail("expected OtherError, got \(error)")
    }
    XCTAssertEqual(provider.callCount, 1)
  }

  // MARK: - Cancellation

  func testCancellationDuringFirstAttemptPreventsTheRetry() async {
    // Escape is deliberate user intent: a retry would restart work just stopped.
    let provider = ScriptedProvider(
      [.failure(ProviderError.timeout), .success("must not be reached")],
      awaitCancellationOnFirstCall: true)

    let task = Task { try await self.run(provider) }
    task.cancel()

    let result = await task.result
    switch result {
    case .success(let value):
      XCTFail("expected cancellation, got \(value)")
    case .failure(let error):
      XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
    }
    XCTAssertEqual(provider.callCount, 1, "a cancelled run must not issue a second request")
  }

  func testCancelledProviderErrorIsNotRetried() async {
    // URLError.cancelled maps to ProviderError.cancelled, which is classified
    // non-retryable, so this path never reaches the checkCancellation guard.
    let provider = ScriptedProvider([.failure(ProviderError.cancelled), .success("unreached")])
    _ = try? await run(provider)
    XCTAssertEqual(provider.callCount, 1)
  }
}
