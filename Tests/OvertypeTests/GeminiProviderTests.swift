import XCTest

@testable import Overtype

final class GeminiProviderTests: XCTestCase {

  private func data(_ string: String) -> Data { Data(string.utf8) }

  // MARK: - Success path (US1)

  func testExtractsTextFromSuccessBody() throws {
    let body = #"""
      {"candidates":[{"content":{"parts":[{"text":"Hello world"}],"role":"model"},
      "finishReason":"STOP"}]}
      """#
    let result = try GeminiProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  func testConcatenatesMultipleParts() throws {
    let body = #"""
      {"candidates":[{"content":{"parts":[{"text":"Hello "},{"text":"world"}],"role":"model"},
      "finishReason":"STOP"}]}
      """#
    let result = try GeminiProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "Hello world")
  }

  func testMaxTokensWithTextIsTreatedAsSuccess() throws {
    let body = #"""
      {"candidates":[{"content":{"parts":[{"text":"partial"}]},"finishReason":"MAX_TOKENS"}]}
      """#
    let result = try GeminiProvider.parseResponseText(from: data(body))
    XCTAssertEqual(result, "partial")
  }

  // MARK: - Failure mapping (US3)

  func testPromptBlockReasonMapsToResponseBlocked() {
    let body = #"{"promptFeedback":{"blockReason":"SAFETY"},"candidates":[]}"#
    assertParseThrows(body) { error in
      guard case ProviderError.responseBlocked(let reason) = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
      XCTAssertEqual(reason, "SAFETY")
    }
  }

  func testSafetyFinishReasonMapsToResponseBlocked() {
    let body = #"{"candidates":[{"content":{"parts":[]},"finishReason":"SAFETY"}]}"#
    assertParseThrows(body) { error in
      guard case ProviderError.responseBlocked = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
    }
  }

  func testNoCandidatesMapsToResponseBlocked() {
    let body = #"{"candidates":[]}"#
    assertParseThrows(body) { error in
      guard case ProviderError.responseBlocked = error else {
        return XCTFail("expected responseBlocked, got \(error)")
      }
    }
  }

  func testEmptyTextMapsToEmptyResponse() {
    let body = #"{"candidates":[{"content":{"parts":[{"text":""}]},"finishReason":"STOP"}]}"#
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

  // MARK: - Endpoint construction (US1)

  func testEndpointUsesDefaultBaseWhenNil() throws {
    let url = try GeminiProvider.endpointURL(base: nil, model: "gemini-3.5-flash-lite")
    XCTAssertEqual(
      url.absoluteString,
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")
  }

  func testEndpointHonorsCustomBaseAndKeepsActionSuffix() throws {
    let url = try GeminiProvider.endpointURL(
      base: URL(string: "https://example.com/v1beta"), model: "m")
    XCTAssertEqual(url.absoluteString, "https://example.com/v1beta/models/m:generateContent")
  }

  // MARK: - Helpers

  private func assertParseThrows(_ body: String, _ check: (Error) -> Void) {
    XCTAssertThrowsError(try GeminiProvider.parseResponseText(from: data(body))) { error in
      check(error)
    }
  }
}
