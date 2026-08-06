import XCTest

@testable import Overtype

final class AnthropicProviderTests: XCTestCase {

  private func data(_ string: String) -> Data { Data(string.utf8) }

  // MARK: - Success path (US1)

  func testExtractsTextFromSuccessBody() throws {
    let body = #"""
      {"id":"msg_01","type":"message","role":"assistant","model":"claude-haiku-4-5",
      "content":[{"type":"text","text":"Hello world"}],"stop_reason":"end_turn"}
      """#
    let result = try AnthropicProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  func testConcatenatesMultipleTextBlocks() throws {
    let body = #"""
      {"content":[{"type":"text","text":"Hello "},{"type":"text","text":"world"}],
      "stop_reason":"end_turn"}
      """#
    let result = try AnthropicProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  func testSkipsThinkingBlocksWhenExtractingText() throws {
    // A "thinking" block carries model reasoning, which must never be typed into
    // the user's document. Reasoning is on by default on the Claude 5 tier and
    // this provider deliberately sends no `thinking` field to suppress it, so
    // the filter is the only thing standing between reasoning and the document.
    let body = #"""
      {"content":[
      {"type":"thinking","thinking":"The user wants the grammar fixed. I should…","signature":"abc"},
      {"type":"text","text":"Hello world"}],"stop_reason":"end_turn"}
      """#
    let result = try AnthropicProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  func testSkipsRedactedThinkingBlocks() throws {
    let body = #"""
      {"content":[{"type":"redacted_thinking","data":"encrypted-blob"},
      {"type":"text","text":"Hello world"}],"stop_reason":"end_turn"}
      """#
    let result = try AnthropicProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  func testSkipsUnrecognizedBlockTypes() throws {
    // Allow-list, not deny-list: a block type that does not exist yet must be
    // skipped rather than written into the user's document.
    let body = #"""
      {"content":[{"type":"some_future_block","text":"do not write me"},
      {"type":"text","text":"Hello world"}],"stop_reason":"end_turn"}
      """#
    let result = try AnthropicProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  func testMaxTokensWithTextIsTreatedAsSuccess() throws {
    // Parity with GeminiProvider's MAX_TOKENS handling: a length-truncated but
    // non-empty result is written like any other output.
    let body = #"""
      {"content":[{"type":"text","text":"partial"}],"stop_reason":"max_tokens"}
      """#
    let result = try AnthropicProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "partial")
  }

  func testMissingStopReasonFallsThroughToExtraction() throws {
    // A body without stop_reason must not be treated as blocked.
    let body = #"{"content":[{"type":"text","text":"Hello world"}]}"#
    let result = try AnthropicProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  // MARK: - Failure mapping (US3)

  func testRefusalMapsToResponseBlocked() {
    let body = #"{"content":[],"stop_reason":"refusal"}"#
    assertParseThrows(body) { error in
      guard case ProviderError.responseBlocked(let reason) = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
      XCTAssertEqual(reason, "refusal")
    }
  }

  func testRefusalIncorporatesStopDetailsCategory() {
    let body = #"""
      {"content":[],"stop_reason":"refusal",
      "stop_details":{"type":"refusal","category":"cyber","explanation":"SECRET-EXPLANATION"}}
      """#
    assertParseThrows(body) { error in
      guard case ProviderError.responseBlocked(let reason) = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
      XCTAssertTrue(reason.contains("cyber"), "expected category in reason, got \(reason)")
      // stop_details.explanation is server-authored prose that may echo the
      // submitted text, and the reason reaches a user-visible message.
      XCTAssertFalse(
        reason.contains("SECRET-EXPLANATION"),
        "explanation must never be included in the reason")
    }
  }

  func testOtherNonNormalStopReasonMapsToResponseBlocked() {
    // pause_turn should be unreachable (no tools are sent), but if it appears it
    // must be reported by name rather than collapsing to an empty result.
    let body = #"{"content":[],"stop_reason":"pause_turn"}"#
    assertParseThrows(body) { error in
      guard case ProviderError.responseBlocked(let reason) = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
      XCTAssertEqual(reason, "pause_turn")
    }
  }

  func testThinkingOnlyContentMapsToEmptyResponse() {
    // Everything filtered out leaves nothing to write.
    let body = #"""
      {"content":[{"type":"thinking","thinking":"reasoning only"}],"stop_reason":"end_turn"}
      """#
    assertParseThrows(body) { error in
      guard case ProviderError.emptyResponse = error else {
        return XCTFail("expected emptyResponse, got \(error)")
      }
    }
  }

  func testEmptyTextMapsToEmptyResponse() {
    let body = #"{"content":[{"type":"text","text":""}],"stop_reason":"end_turn"}"#
    assertParseThrows(body) { error in
      guard case ProviderError.emptyResponse = error else {
        return XCTFail("expected emptyResponse, got \(error)")
      }
    }
  }

  func testMalformedBodyMapsToInvalidResponse() {
    assertParseThrows("this is not json") { error in
      guard case ProviderError.invalidResponse = error else {
        return XCTFail("expected invalidResponse, got \(error)")
      }
    }
  }

  func testMissingContentArrayMapsToInvalidResponse() {
    assertParseThrows(#"{"stop_reason":"end_turn"}"#) { error in
      guard case ProviderError.invalidResponse = error else {
        return XCTFail("expected invalidResponse, got \(error)")
      }
    }
  }

  func testRefusalWithoutContentStillMapsToResponseBlocked() {
    // The stop-reason check runs before the `content` guard, so a decline that
    // omits `content` entirely still reports its reason instead of degrading to
    // the generic `.invalidResponse`.
    assertParseThrows(#"{"stop_reason":"refusal"}"#) { error in
      guard case ProviderError.responseBlocked(let reason) = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
      XCTAssertEqual(reason, "refusal")
    }
  }

  // MARK: - Request body (US1) — the deliberate omissions must stay omitted

  func testRequestBodyNeverCarriesSamplingParameters() {
    let body = AnthropicProvider.requestBody(
      model: "claude-haiku-4-5", systemPrompt: "sys", userPrompt: "user")
    // Load-bearing: models in the Opus 4.7+/Opus 5/Sonnet 5/Fable 5 generation
    // reject these with HTTP 400. `requestBody` takes no temperature argument,
    // so this asserts the seam cannot regress even if a caller wanted to pass one.
    XCTAssertNil(body["temperature"])
    XCTAssertNil(body["top_p"])
    XCTAssertNil(body["top_k"])
  }

  func testRequestBodyOmitsThinkingAndEffort() {
    let body = AnthropicProvider.requestBody(
      model: "claude-haiku-4-5", systemPrompt: "sys", userPrompt: "user")
    XCTAssertNil(body["thinking"])
    // `effort` is only ever nested inside `output_config`, never top-level, so
    // asserting the container is the meaningful check.
    XCTAssertNil(body["output_config"])
  }

  func testRequestBodyPutsSystemPromptAtTopLevel() {
    // A {"role": "system"} entry inside `messages` is a validation error on this
    // API; the system prompt must be a sibling of `messages`.
    //
    // The two prompts use distinct sentinels on purpose: with both set to the
    // literal "user", a role/content swap would still satisfy every assertion.
    let body = AnthropicProvider.requestBody(
      model: "claude-haiku-4-5",
      systemPrompt: "SYSTEM-SENTINEL",
      userPrompt: "USER-SENTINEL")
    XCTAssertEqual(body["system"] as? String, "SYSTEM-SENTINEL")

    guard let messages = body["messages"] as? [[String: Any]] else {
      return XCTFail("expected a messages array, got \(String(describing: body["messages"]))")
    }
    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages.first?["role"] as? String, "user")
    XCTAssertEqual(messages.first?["content"] as? String, "USER-SENTINEL")
    // The system prompt must not leak into the message turn.
    XCTAssertNil(messages.first?["system"])
  }

  func testRequestBodyAlwaysCarriesRequiredFields() {
    // `max_tokens` and `model` are both required; a request without either is
    // rejected outright.
    let body = AnthropicProvider.requestBody(
      model: "claude-haiku-4-5", systemPrompt: "sys", userPrompt: "user")
    XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5")
    XCTAssertEqual(body["max_tokens"] as? Int, 8192)
  }

  // MARK: - Endpoint construction (US1)

  func testEndpointUsesDefaultBaseWhenNil() throws {
    let url = try AnthropicProvider.endpointURL(base: nil)
    XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/v1/messages")
  }

  func testEndpointHonorsCustomBaseWithTrailingSlash() throws {
    let url = try AnthropicProvider.endpointURL(base: URL(string: "https://example.com/v1/"))
    XCTAssertEqual(url.absoluteString, "https://example.com/v1/messages")
  }

  func testEndpointHonorsCustomBaseWithoutTrailingSlash() throws {
    let url = try AnthropicProvider.endpointURL(base: URL(string: "https://example.com/v1"))
    XCTAssertEqual(url.absoluteString, "https://example.com/v1/messages")
  }

  // MARK: - Helpers

  private func assertParseThrows(_ body: String, _ check: (Error) -> Void) {
    XCTAssertThrowsError(try AnthropicProvider.parseResponseText(from: data(body))) { error in
      check(error)
    }
  }
}
