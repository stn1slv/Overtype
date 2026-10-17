import XCTest

@testable import Overtype

/// H5: the `openai` kind was the only provider without response-parsing seams
/// or tests, and the least defended: refusals degraded to a generic error,
/// content-filter stops looked like normal output, empty content was returned
/// as success, and inline reasoning markers were typed into the document.
/// Contract: specs/009-stability-hardening/contracts/openai-response-handling.md.
final class OpenAICompatibleProviderTests: XCTestCase {

  // MARK: - Endpoint URL

  func testEndpointURLAppendsPath() throws {
    let url = try OpenAICompatibleProvider.endpointURL(base: URL(string: "https://api.openai.com/v1"))
    XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
  }

  func testEndpointURLNormalizesTrailingSlash() throws {
    let url = try OpenAICompatibleProvider.endpointURL(
      base: URL(string: "https://api.openai.com/v1/"))
    XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
  }

  func testEndpointURLThrowsOnNilBase() {
    XCTAssertThrowsError(try OpenAICompatibleProvider.endpointURL(base: nil)) { error in
      guard case ProviderError.invalidURL = error else {
        return XCTFail("expected invalidURL, got \(error)")
      }
    }
  }

  // MARK: - Request body (specs/010-model-aware-parameters)

  private func body(temperature: Double?, reasoning: ReasoningSetting?) -> [String: Any] {
    OpenAICompatibleProvider.requestBody(
      model: "gpt-6-luna", systemPrompt: "sys", userPrompt: "user", temperature: temperature,
      reasoning: reasoning)
  }

  func testRequestBodyOnAutomaticCarriesOnlyModelAndMessages() {
    XCTAssertEqual(Set(body(temperature: nil, reasoning: nil).keys), ["model", "messages"])
  }

  func testRequestBodySendsReasoningEffort() {
    let sent = body(temperature: nil, reasoning: .level("none"))
    XCTAssertEqual(sent["reasoning_effort"] as? String, "none")
    XCTAssertNil(sent["temperature"])
  }

  func testRequestBodySendsTemperatureOnlyWhenSet() {
    let sent = body(temperature: 0, reasoning: .level("none"))
    XCTAssertEqual(sent["temperature"] as? Double, 0)
    XCTAssertEqual(Set(sent.keys), ["model", "messages", "temperature", "reasoning_effort"])
  }

  func testRequestBodyIgnoresAThinkingBudget() {
    // Budgets exist only for Gemini; the resolver never produces one here.
    XCTAssertNil(body(temperature: nil, reasoning: .thinkingBudget(0))["reasoning_effort"])
  }

  // MARK: - Response parsing

  private func parse(_ json: String) throws -> String {
    try OpenAICompatibleProvider.parseResponseText(from: Data(json.utf8))
  }

  func testNormalContentIsReturned() throws {
    let json = #"{"choices": [{"message": {"content": "Fixed text."}}]}"#
    XCTAssertEqual(try parse(json), "Fixed text.")
  }

  func testRefusalWithNullContentMapsToResponseBlocked() {
    let json = #"""
      {"choices": [{"message": {"content": null, "refusal": "I cannot help with that."},
                    "finish_reason": "stop"}]}
      """#
    XCTAssertThrowsError(try parse(json)) { error in
      guard case ProviderError.responseBlocked(let reason) = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
      // The category, never the server-authored refusal text (Principle V).
      XCTAssertFalse(reason.contains("cannot help"))
    }
  }

  func testContentFilterFinishReasonMapsToResponseBlocked() {
    let json = #"""
      {"choices": [{"message": {"content": "partial"}, "finish_reason": "content_filter"}]}
      """#
    XCTAssertThrowsError(try parse(json)) { error in
      guard case ProviderError.responseBlocked = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
    }
  }

  func testLengthFinishReasonMapsToOutputTruncated() {
    // "length" means the tail of the output is missing; writing the partial
    // content would silently lose the end of the user's text.
    let json = #"""
      {"choices": [{"message": {"content": "The cat sl"}, "finish_reason": "length"}]}
      """#
    XCTAssertThrowsError(try parse(json)) { error in
      guard case ProviderError.outputTruncated = error else {
        return XCTFail("expected outputTruncated, got \(error)")
      }
    }
    XCTAssertFalse(ProviderError.outputTruncated.isRetryable)
  }

  func testMissingContentWithoutRefusalMapsToInvalidResponse() {
    let json = #"{"choices": [{"message": {"role": "assistant"}}]}"#
    XCTAssertThrowsError(try parse(json)) { error in
      guard case ProviderError.invalidResponse = error else {
        return XCTFail("expected invalidResponse, got \(error)")
      }
    }
  }

  func testEmptyChoicesMapsToInvalidResponse() {
    XCTAssertThrowsError(try parse(#"{"choices": []}"#)) { error in
      guard case ProviderError.invalidResponse = error else {
        return XCTFail("expected invalidResponse, got \(error)")
      }
    }
  }

  func testEmptyContentMapsToEmptyResponse() {
    let json = #"{"choices": [{"message": {"content": "   "}}]}"#
    XCTAssertThrowsError(try parse(json)) { error in
      guard case ProviderError.emptyResponse = error else {
        return XCTFail("expected emptyResponse, got \(error)")
      }
    }
  }

  func testLeadingReasoningBlockIsStripped() throws {
    let json = #"""
      {"choices": [{"message": {"content": "<think>The subject is singular.</think>\nThe cat sleeps."}}]}
      """#
    XCTAssertEqual(try parse(json), "The cat sleeps.")
  }

  func testOrphanReasoningPrefixIsStripped() throws {
    // DeepSeek-R1 template shape: bare reasoning ending in a lone </think>.
    let json = #"""
      {"choices": [{"message": {"content": "Okay, checking the grammar.\n</think>\nThe cat sleeps."}}]}
      """#
    XCTAssertEqual(try parse(json), "The cat sleeps.")
  }

  func testUnterminatedReasoningBlockMapsToEmptyResponse() {
    let json = #"{"choices": [{"message": {"content": "<think>never closed"}}]}"#
    XCTAssertThrowsError(try parse(json)) { error in
      guard case ProviderError.emptyResponse = error else {
        return XCTFail("expected emptyResponse, got \(error)")
      }
    }
  }
}
