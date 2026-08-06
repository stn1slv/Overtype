import XCTest

@testable import Overtype

/// Covers the pure logic of `OllamaProvider`: endpoint construction, request
/// body shape, the pre-send size check, reasoning stripping, response parsing,
/// error extraction, and transport-failure mapping.
///
/// No system boundary is touched. The real HTTP call, the App Transport
/// Security behaviour of the bundle, and the offline run are covered by the
/// manual acceptance procedure in specs/008-ollama-provider/quickstart.md
/// (Principle VIII).
final class OllamaProviderTests: XCTestCase {

  // MARK: - endpointURL

  func testEndpointUsesLocalDefaultWhenBaseIsNil() throws {
    let url = try OllamaProvider.endpointURL(base: nil)
    XCTAssertEqual(url.absoluteString, "http://localhost:11434/api/chat")
  }

  func testEndpointAppendsPathWithoutDoublingSlash() throws {
    let withSlash = try OllamaProvider.endpointURL(base: URL(string: "http://localhost:11434/"))
    let withoutSlash = try OllamaProvider.endpointURL(base: URL(string: "http://localhost:11434"))
    XCTAssertEqual(withSlash.absoluteString, "http://localhost:11434/api/chat")
    XCTAssertEqual(withoutSlash.absoluteString, "http://localhost:11434/api/chat")
  }

  func testEndpointHonoursCustomHostAndPort() throws {
    let url = try OllamaProvider.endpointURL(base: URL(string: "http://192.168.1.50:9999"))
    XCTAssertEqual(url.absoluteString, "http://192.168.1.50:9999/api/chat")
  }

  // MARK: - requestBody

  private func sampleBody(temperature: Double = 0.25) -> [String: Any] {
    return OllamaProvider.requestBody(
      model: "llama3.2",
      systemPrompt: "You fix grammar.",
      userPrompt: "Fix: the cat are sleeping",
      temperature: temperature)
  }

  func testRequestBodyCarriesModelAndRoles() {
    let body = sampleBody()
    XCTAssertEqual(body["model"] as? String, "llama3.2")

    guard let messages = body["messages"] as? [[String: String]] else {
      return XCTFail("messages missing or wrong shape")
    }
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[0]["role"], "system")
    XCTAssertEqual(messages[0]["content"], "You fix grammar.")
    XCTAssertEqual(messages[1]["role"], "user")
    XCTAssertEqual(messages[1]["content"], "Fix: the cat are sleeping")
  }

  func testRequestBodyDisablesStreaming() {
    // Load-bearing: this endpoint streams by default, and a streamed body is
    // newline-delimited JSON that would fail to parse and could write a partial
    // answer over the user's selection.
    XCTAssertEqual(sampleBody()["stream"] as? Bool, false)
  }

  func testRequestBodySendsTemperatureAndContextWindow() {
    guard let options = sampleBody(temperature: 0.7)["options"] as? [String: Any] else {
      return XCTFail("options missing")
    }
    XCTAssertEqual(options["temperature"] as? Double, 0.7)
    XCTAssertEqual(options["num_ctx"] as? Int, OllamaProvider.contextWindowTokens)
  }

  func testRequestBodyKeySetIsExactlyTheDocumentedOne() {
    // Negative assertion, deliberately strict: it is what stops `keep_alive`,
    // `think` or `num_predict` from being reintroduced later. Each is omitted
    // for a recorded reason (see the comment on `requestBody`).
    XCTAssertEqual(Set(sampleBody().keys), ["model", "messages", "stream", "options"])

    guard let options = sampleBody()["options"] as? [String: Any] else {
      return XCTFail("options missing")
    }
    XCTAssertEqual(Set(options.keys), ["temperature", "num_ctx"])
  }

  // MARK: - checkInputSize (FR-010b)

  func testInputAtTheLimitIsAccepted() {
    let text = String(repeating: "a", count: OllamaProvider.maxSafeInputCharacters)
    XCTAssertNoThrow(try OllamaProvider.checkInputSize(text))
  }

  func testInputAboveTheLimitIsRefusedWithTheLimitAttached() {
    let text = String(repeating: "a", count: OllamaProvider.maxSafeInputCharacters + 1)
    do {
      try OllamaProvider.checkInputSize(text)
      XCTFail("expected an oversized selection to be refused")
    } catch let error as ProviderError {
      guard case .inputTooLargeForContext(let limit) = error else {
        return XCTFail("expected inputTooLargeForContext, got \(error)")
      }
      XCTAssertEqual(limit, OllamaProvider.maxSafeInputCharacters)
    } catch {
      XCTFail("expected ProviderError, got \(error)")
    }
  }

  func testTheSizeBoundFitsAWorstCaseInputAndItsRewriteInTheWindow() {
    // Guards the actual invariant, not a ratio fitted to pass. Two things the
    // previous version of this test got wrong: it assumed an English token
    // ratio, and it budgeted nothing for the answer.
    //
    // Worst case is a script tokenising at ~1 token per character (CJK), and an
    // in-place rewrite is about as long as its input, so the window must hold
    // input + answer + the system prompt.
    let worstCaseInputTokens = OllamaProvider.maxSafeInputCharacters
    let worstCaseAnswerTokens = OllamaProvider.maxSafeInputCharacters
    let systemPromptAllowance = 512

    XCTAssertLessThanOrEqual(
      worstCaseInputTokens + worstCaseAnswerTokens + systemPromptAllowance,
      OllamaProvider.contextWindowTokens,
      "a maximum-length selection and its rewrite must fit the context window "
        + "even at one token per character, or the service silently truncates the prompt")
  }

  func testTheSizeBoundNeverRefusesASelectionTheDefaultActionCapAllows() {
    // The default ActionConfig.maxInputCharacters is 5000. If the provider
    // bound dropped below it, ordinary out-of-the-box selections would start
    // being refused.
    XCTAssertGreaterThanOrEqual(OllamaProvider.maxSafeInputCharacters, 5000)
  }

  // MARK: - stripLeadingReasoningBlock (FR-009 layer 2)

  func testLeadingThinkBlockIsRemoved() {
    let result = OllamaProvider.stripLeadingReasoningBlock(
      "<think>The subject is singular.</think>The cat is sleeping.")
    XCTAssertEqual(result, "The cat is sleeping.")
  }

  func testLeadingThinkingBlockIsRemoved() {
    let result = OllamaProvider.stripLeadingReasoningBlock(
      "<thinking>reasoning here</thinking>\n\nThe cat is sleeping.")
    XCTAssertEqual(result, "The cat is sleeping.")
  }

  func testMarkerMatchingIsCaseInsensitive() {
    let result = OllamaProvider.stripLeadingReasoningBlock(
      "<THINK>reasoning</THINK>The cat is sleeping.")
    XCTAssertEqual(result, "The cat is sleeping.")
  }

  func testPlainAnswerIsUnchanged() {
    XCTAssertEqual(
      OllamaProvider.stripLeadingReasoningBlock("The cat is sleeping."), "The cat is sleeping.")
  }

  func testMarkerInTheMiddleIsLeftAlone() {
    // The user may legitimately be asking Overtype to rewrite text that
    // contains these tags. Only a block at the very start is reasoning.
    let text = "Use the <think> tag to mark reasoning.</think> That is the convention."
    XCTAssertEqual(OllamaProvider.stripLeadingReasoningBlock(text), text)
  }

  func testUnterminatedReasoningYieldsEmpty() {
    // The whole response is reasoning. Empty becomes .emptyResponse upstream,
    // which fails visibly instead of writing scratch work into the document.
    XCTAssertEqual(OllamaProvider.stripLeadingReasoningBlock("<think>still thinking"), "")
  }

  func testEmptyReasoningBlockWithNoAnswerYieldsEmpty() {
    XCTAssertEqual(OllamaProvider.stripLeadingReasoningBlock("<think></think>   "), "")
  }

  func testConsecutiveReasoningBlocksAreAllRemoved() {
    // A single pass would leave the second block in the user's document, which
    // is precisely the leak this filter exists to prevent.
    let result = OllamaProvider.stripLeadingReasoningBlock(
      "<think>first pass</think><think>second pass</think>The cat is sleeping.")
    XCTAssertEqual(result, "The cat is sleeping.")
  }

  func testConsecutiveBlocksWithMixedTagsAndSpacingAreAllRemoved() {
    let result = OllamaProvider.stripLeadingReasoningBlock(
      "<think>one</think>\n\n<thinking>two</thinking>\n<THINK>three</THINK>  Answer.")
    XCTAssertEqual(result, "Answer.")
  }

  func testConsecutiveBlocksWithNoAnswerYieldEmpty() {
    XCTAssertEqual(
      OllamaProvider.stripLeadingReasoningBlock("<think>one</think><thinking>two</thinking>"), "")
  }

  func testUnterminatedSecondBlockYieldsEmpty() {
    // The first block closes, the second never does: everything after it is
    // reasoning, so nothing may be written.
    XCTAssertEqual(
      OllamaProvider.stripLeadingReasoningBlock("<think>one</think><think>still going"), "")
  }

  // MARK: - parseResponseText (FR-009 layer 1)

  private func responseData(_ message: [String: Any]) -> Data {
    let json: [String: Any] = [
      "model": "llama3.2", "created_at": "2026-08-06T10:00:00Z",
      "message": message, "done": true, "done_reason": "stop",
    ]
    // Test fixture built from a literal dictionary; failure here is a bug in
    // the test, not in production code.
    return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
  }

  func testParsesAnswerFromContent() throws {
    let data = responseData(["role": "assistant", "content": "The cat is sleeping."])
    XCTAssertEqual(try OllamaProvider.parseResponseText(from: data), "The cat is sleeping.")
  }

  func testThinkingFieldIsNeverWritten() throws {
    // The highest-risk failure in this feature: reasoning reported in its own
    // field must not reach the user's document.
    let data = responseData([
      "role": "assistant",
      "content": "The cat is sleeping.",
      "thinking": "The subject is singular so the verb must be singular.",
    ])
    let result = try OllamaProvider.parseResponseText(from: data)
    XCTAssertEqual(result, "The cat is sleeping.")
    XCTAssertFalse(result.contains("singular"))
  }

  func testInlineReasoningIsStrippedDuringParsing() throws {
    let data = responseData([
      "role": "assistant", "content": "<think>hmm</think>The cat is sleeping.",
    ])
    XCTAssertEqual(try OllamaProvider.parseResponseText(from: data), "The cat is sleeping.")
  }

  func testEmptyContentIsAnEmptyResponseError() {
    let data = responseData(["role": "assistant", "content": "   "])
    XCTAssertThrowsError(try OllamaProvider.parseResponseText(from: data)) { error in
      guard case ProviderError.emptyResponse = error else {
        return XCTFail("expected emptyResponse, got \(error)")
      }
    }
  }

  func testReasoningOnlyContentIsAnEmptyResponseError() {
    let data = responseData(["role": "assistant", "content": "<think>only reasoning"])
    XCTAssertThrowsError(try OllamaProvider.parseResponseText(from: data)) { error in
      guard case ProviderError.emptyResponse = error else {
        return XCTFail("expected emptyResponse, got \(error)")
      }
    }
  }

  func testMalformedBodyIsAnInvalidResponseError() {
    XCTAssertThrowsError(
      try OllamaProvider.parseResponseText(from: Data("not json".utf8))
    ) { error in
      guard case ProviderError.invalidResponse = error else {
        return XCTFail("expected invalidResponse, got \(error)")
      }
    }
  }

  func testBodyWithoutMessageContentIsAnInvalidResponseError() {
    let data = responseData(["role": "assistant"])
    XCTAssertThrowsError(try OllamaProvider.parseResponseText(from: data)) { error in
      guard case ProviderError.invalidResponse = error else {
        return XCTFail("expected invalidResponse, got \(error)")
      }
    }
  }

  // MARK: - extractErrorMessage

  func testExtractsOllamaStringShapedError() {
    let data = Data(#"{"error":"model \"nope\" not found, try pulling it first"}"#.utf8)
    XCTAssertEqual(
      OllamaProvider.extractErrorMessage(from: data),
      "model \"nope\" not found, try pulling it first")
  }

  func testFallsBackToTheOpenAIShapedExtractor() {
    // Not Ollama's own shape, but the shared extractor understands it and its
    // truncated-raw-body safety net is reused rather than duplicated.
    let data = Data(#"{"error":{"message":"something else"}}"#.utf8)
    XCTAssertEqual(OllamaProvider.extractErrorMessage(from: data), "something else")
  }

  func testFallsBackToRawBodyWhenNotJSON() {
    let message = OllamaProvider.extractErrorMessage(from: Data("plain text failure".utf8))
    XCTAssertEqual(message, "plain text failure")
  }

  // MARK: - isModelNotFound

  func testModelNotFoundNeedsBoth404AndTheMessage() {
    let notFoundBody = Data(#"{"error":"model \"nope\" not found, try pulling it first"}"#.utf8)
    let otherBody = Data(#"{"error":"invalid options"}"#.utf8)

    XCTAssertTrue(OllamaProvider.isModelNotFound(status: 404, body: notFoundBody))
    XCTAssertFalse(
      OllamaProvider.isModelNotFound(status: 404, body: otherBody),
      "a 404 that is not about a model must stay a generic API error")
    XCTAssertFalse(
      OllamaProvider.isModelNotFound(status: 500, body: notFoundBody),
      "a server fault must stay retryable rather than becoming a permanent error")
  }

  func testModelNotFoundMatchesTheWordingThisVersionActuallySends() {
    // Captured from Ollama 0.32.5, which omits the documented "try pulling it
    // first" suffix and uses single quotes.
    let body = Data(#"{"error":"model 'does-not-exist-xyz' not found"}"#.utf8)
    XCTAssertTrue(OllamaProvider.isModelNotFound(status: 404, body: body))
  }

  func testProxyHTMLNotFoundPageIsNotAMissingModel() {
    // A remote endpoint behind a proxy answers a bad path with an HTML page
    // containing "Not Found". Reading that as a missing model would send the
    // user to install a model when their address is wrong — and permanently,
    // because the error is non-retryable.
    let html = Data(
      "<html><head><title>404 Not Found</title></head><body>Not Found</body></html>".utf8)
    XCTAssertFalse(OllamaProvider.isModelNotFound(status: 404, body: html))
  }

  func testNonStringErrorFieldIsNotAMissingModel() {
    // OpenAI-shaped bodies nest an object under "error"; that is not Ollama's
    // shape and must not be read as a model failure.
    let body = Data(#"{"error":{"message":"resource not found"}}"#.utf8)
    XCTAssertFalse(OllamaProvider.isModelNotFound(status: 404, body: body))
  }

  // MARK: - displayAddress

  func testDisplayAddressKeepsThePort() {
    // The point of .serviceUnreachable is naming the address that failed; a
    // bare "localhost" tells a user on a custom port nothing.
    guard let url = URL(string: "http://localhost:11435/api/chat") else {
      return XCTFail("bad test URL")
    }
    XCTAssertEqual(OllamaProvider.displayAddress(for: url), "localhost:11435")
  }

  func testDisplayAddressOmitsAnAbsentPort() throws {
    guard let url = URL(string: "http://my-ollama-box/api/chat") else {
      return XCTFail("bad test URL")
    }
    XCTAssertEqual(OllamaProvider.displayAddress(for: url), "my-ollama-box")
  }

  // MARK: - mapTransportFailure

  func testConnectionFailuresBecomeServiceUnreachable() {
    for code in [URLError.cannotConnectToHost, .cannotFindHost] {
      let mapped = OllamaProvider.mapTransportFailure(URLError(code), address: "localhost:11434")
      guard case ProviderError.serviceUnreachable(let address) = mapped else {
        return XCTFail("expected serviceUnreachable for \(code), got \(mapped)")
      }
      XCTAssertEqual(address, "localhost:11434")
    }
  }

  func testDroppedConnectionStaysTransientAndRetryable() {
    // .networkConnectionLost means the connection was established and then
    // dropped, which proves the service was reachable. Mapping it to the
    // permanent .serviceUnreachable would skip the retry every other provider
    // gets and tell the user to start a service that is already running.
    let mapped = OllamaProvider.mapTransportFailure(
      URLError(.networkConnectionLost), address: "localhost:11434")
    guard case ProviderError.networkError = mapped else {
      return XCTFail("expected networkError, got \(mapped)")
    }
    XCTAssertTrue(mapped.isRetryable, "a dropped connection must still be retried once")
  }

  func testTimeoutAndCancellationKeepTheirSharedMeaning() {
    guard
      case ProviderError.timeout = OllamaProvider.mapTransportFailure(
        URLError(.timedOut), address: "localhost")
    else {
      return XCTFail("timeout must not be reclassified")
    }
    guard
      case ProviderError.cancelled = OllamaProvider.mapTransportFailure(
        URLError(.cancelled), address: "localhost")
    else {
      return XCTFail("cancellation must not be reclassified")
    }
  }

  func testOtherTransportFailuresStayNetworkErrors() {
    let mapped = OllamaProvider.mapTransportFailure(
      URLError(.secureConnectionFailed), address: "localhost")
    guard case ProviderError.networkError = mapped else {
      return XCTFail("expected networkError, got \(mapped)")
    }
  }

  // MARK: - Credential handling (FR-005, FR-006)

  func testNoKeychainKeyMeansNoAuthorizationHeader() {
    XCTAssertNil(OllamaProvider.authorizationHeader(forKeychainKey: nil))
    XCTAssertNil(OllamaProvider.authorizationHeader(forKeychainKey: ""))
  }

  func testKeychainKeyPointingAtNothingMeansNoAuthorizationHeader() {
    // The state a provider created in Settings with an empty key field is in:
    // `saveProvider` assigns a keychainKey but stores no entry. This must be a
    // supported keyless configuration, not a missing-credential failure.
    let unusedKey = "overtype-test-nonexistent-\(UUID().uuidString)"
    XCTAssertNil(OllamaProvider.authorizationHeader(forKeychainKey: unusedKey))
  }

  func testStoredCredentialProducesABearerHeader() throws {
    // The only coverage of the credential path: every manual acceptance item
    // runs keyless against a local service.
    let key = "overtype-test-ollama-\(UUID().uuidString)"
    try KeychainStore.shared.store(key: key, value: "secret-token")
    defer { try? KeychainStore.shared.delete(key: key) }

    XCTAssertEqual(
      OllamaProvider.authorizationHeader(forKeychainKey: key), "Bearer secret-token")
  }
}
