import XCTest

@testable import Overtype

final class ProviderErrorMessageTests: XCTestCase {

  private func data(_ string: String) -> Data { Data(string.utf8) }

  func testExtractsOpenAIStyleErrorMessage() {
    let body = #"{"error": {"message": "Invalid API key", "type": "auth"}}"#
    let result = OpenAICompatibleProvider.extractErrorMessage(from: data(body))
    XCTAssertEqual(result, "Invalid API key")
  }

  func testFallsBackToRawBodyWhenNotOpenAIShaped() {
    let body = "Service Unavailable"
    let result = OpenAICompatibleProvider.extractErrorMessage(from: data(body))
    XCTAssertEqual(result, "Service Unavailable")
  }

  func testEmptyBodyReturnsPlaceholder() {
    let result = OpenAICompatibleProvider.extractErrorMessage(from: Data())
    XCTAssertEqual(result, "Server returned an error with no readable body.")
  }

  func testParameterRejectedReadsLikeAnAPIError() {
    let error = ProviderError.parameterRejected(
      .temperature, statusCode: 400, message: "Unsupported value: 'temperature'")
    XCTAssertEqual(error.errorDescription, "API Error 400: Unsupported value: 'temperature'")
  }

  func testParameterRejectedLogLabelNeverCarriesTheMessage() {
    // The server message can echo submitted text (Principle V).
    let error = ProviderError.parameterRejected(
      .reasoning, statusCode: 400, message: "secret selection text")
    XCTAssertEqual(error.logLabel, "HTTP 400 (rejected parameter: reasoning)")
    XCTAssertFalse(error.logLabel.contains("secret"))
  }

  // MARK: - Rejected parameter classification (specs/010, US3)

  func testExtractsRejectedTemperature() {
    let body =
      #"{"error": {"message": "x", "type": "invalid_request_error", "param": "temperature"}}"#
    XCTAssertEqual(
      OpenAICompatibleProvider.extractRejectedParameter(from: data(body)), .temperature)
  }

  func testExtractsRejectedReasoningEffort() {
    let body = #"{"error": {"message": "x", "param": "reasoning_effort"}}"#
    XCTAssertEqual(
      OpenAICompatibleProvider.extractRejectedParameter(from: data(body)), .reasoning)
  }

  func testOtherOrMissingParamIsNotDroppable() {
    XCTAssertNil(
      OpenAICompatibleProvider.extractRejectedParameter(
        from: data(#"{"error": {"message": "x", "param": "service_tier"}}"#)))
    XCTAssertNil(
      OpenAICompatibleProvider.extractRejectedParameter(
        from: data(#"{"error": {"message": "temperature is not supported"}}"#)))
    XCTAssertNil(OpenAICompatibleProvider.extractRejectedParameter(from: data("not json")))
  }

  func testLongRawBodyIsTruncated() {
    let body = String(repeating: "x", count: 500)
    let result = OpenAICompatibleProvider.extractErrorMessage(from: data(body))
    XCTAssertTrue(result.hasSuffix("…"))
    // 200 characters plus the ellipsis.
    XCTAssertEqual(result.count, 201)
  }
}
