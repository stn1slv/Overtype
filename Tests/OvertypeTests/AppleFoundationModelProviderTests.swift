import FoundationModels
import XCTest

@testable import Overtype

/// specs/011-apple-foundation-models. The mapping tests build real framework
/// values through their public initializers (no mocks, Principle VIII) and
/// need macOS 27. The model call itself is covered by the manual acceptance
/// in docs/compatibility.md.
final class AppleFoundationModelProviderTests: XCTestCase {

  private func provider() -> AppleFoundationModelProvider {
    AppleFoundationModelProvider(
      config: ProviderConfig(
        id: "apple", kind: .apple, baseURL: nil, defaultModel: "system", timeoutSeconds: 30,
        keychainKey: nil))
  }

  private func request(model: String) -> TransformRequest {
    TransformRequest(
      text: "t", systemPrompt: "s", userPromptTemplate: "{{text}}", model: model,
      temperature: nil)
  }

  // MARK: - Model name (research R13)

  func testAcceptsEmptyAndSystemOnly() {
    XCTAssertTrue(AppleFoundationModelProvider.acceptsModel(""))
    XCTAssertTrue(AppleFoundationModelProvider.acceptsModel("system"))
    XCTAssertFalse(AppleFoundationModelProvider.acceptsModel("pcc"))
    XCTAssertFalse(AppleFoundationModelProvider.acceptsModel("System"))
  }

  func testUnknownModelFailsBeforeTheModelIsUsed() async {
    let expected: ProviderError
    if #available(macOS 27, *) {
      expected = .modelNotAvailable(model: "other")
    } else {
      expected = .onDeviceModelUnavailable(.operatingSystemTooOld)
    }
    do {
      _ = try await provider().transform(request(model: "other"))
      XCTFail("expected \(expected)")
    } catch let error as ProviderError {
      XCTAssertEqual(error.logLabel, expected.logLabel)
      XCTAssertEqual(error.errorDescription, expected.errorDescription)
    } catch {
      XCTFail("unexpected \(error)")
    }
  }

  func testTimeoutConversionGuardsHandEditedValues() {
    XCTAssertEqual(AppleFoundationModelProvider.nanoseconds(forTimeout: 60), 60_000_000_000)
    XCTAssertEqual(AppleFoundationModelProvider.nanoseconds(forTimeout: 0), 30_000_000_000)
    XCTAssertEqual(AppleFoundationModelProvider.nanoseconds(forTimeout: -5), 30_000_000_000)
    XCTAssertEqual(AppleFoundationModelProvider.nanoseconds(forTimeout: .nan), 30_000_000_000)
    XCTAssertEqual(AppleFoundationModelProvider.nanoseconds(forTimeout: 1e12), 3_600_000_000_000)
  }

  // MARK: - Availability mapping (research R4)

  func testAvailabilityReasons() throws {
    guard #available(macOS 27, *) else { throw XCTSkip("needs macOS 27") }
    let map = AppleFoundationModelProvider.error(for:)
    XCTAssertEqual(
      map(.deviceNotEligible).errorDescription,
      ProviderError.onDeviceModelUnavailable(.deviceNotEligible).errorDescription)
    XCTAssertEqual(
      map(.appleIntelligenceNotEnabled).errorDescription,
      ProviderError.onDeviceModelUnavailable(.appleIntelligenceNotEnabled).errorDescription)
    XCTAssertEqual(
      map(.modelNotReady).errorDescription,
      ProviderError.onDeviceModelUnavailable(.modelNotReady).errorDescription)
  }

  // MARK: - Framework error mapping (research R5)

  private func assertMaps(
    _ error: Error, to expected: ProviderError, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    guard #available(macOS 27, *) else { throw XCTSkip("needs macOS 27") }
    let mapped = AppleFoundationModelProvider.providerError(from: error)
    XCTAssertEqual(mapped.logLabel, expected.logLabel, file: file, line: line)
    XCTAssertEqual(mapped.errorDescription, expected.errorDescription, file: file, line: line)
  }

  func testContextSizeExceeded() throws {
    guard #available(macOS 27, *) else { throw XCTSkip("needs macOS 27") }
    try assertMaps(
      LanguageModelError.contextSizeExceeded(
        .init(contextSize: 8192, tokenCount: 10428, debugDescription: "")),
      to: .contextWindowExceeded(tokenLimit: 8192))
  }

  func testRateLimitedGuardrailAndRefusal() throws {
    guard #available(macOS 27, *) else { throw XCTSkip("needs macOS 27") }
    try assertMaps(
      LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "")),
      to: .rateLimited)
    try assertMaps(
      LanguageModelError.guardrailViolation(.init(debugDescription: "")),
      to: .responseBlocked(reason: "the on-device safety guardrails"))
    try assertMaps(
      LanguageModelError.refusal(.init(explanation: "no", debugDescription: "")),
      to: .responseBlocked(reason: "the on-device model refused"))
  }

  func testLanguageAndTimeout() throws {
    guard #available(macOS 27, *) else { throw XCTSkip("needs macOS 27") }
    try assertMaps(
      LanguageModelError.unsupportedLanguageOrLocale(
        .init(languageCode: Locale.LanguageCode("cy"), debugDescription: "")),
      to: .unsupportedLanguage(code: "cy"))
    try assertMaps(LanguageModelError.timeout(.init(debugDescription: "")), to: .timeout)
  }

  func testOtherFrameworkFailures() throws {
    guard #available(macOS 27, *) else { throw XCTSkip("needs macOS 27") }
    let capability = LanguageModelError.unsupportedCapability(
      .init(capability: .reasoning, debugDescription: ""))
    let mapped = AppleFoundationModelProvider.providerError(from: capability)
    XCTAssertEqual(mapped.logLabel, "on-device model failed")
    try assertMaps(
      SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "")),
      to: .onDeviceModelUnavailable(.modelNotReady))
  }

  func testNonFrameworkErrors() throws {
    try assertMaps(CancellationError(), to: .cancelled)
    try assertMaps(ProviderError.emptyResponse, to: .emptyResponse)
    let other = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "Odd."])
    try assertMaps(other, to: .onDeviceModelFailed(message: "Odd"))
  }
}
