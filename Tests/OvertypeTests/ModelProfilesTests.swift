import XCTest

@testable import Overtype

/// specs/010-model-aware-parameters: built-in model profiles. The expected
/// table below mirrors contracts/model-profiles.md row by row, so a profile
/// cannot drift from the documented contract without a test failing.
final class ModelProfilesTests: XCTestCase {

  // MARK: - Matching (research R5)

  func testExactIDMatches() {
    XCTAssertEqual(
      ModelProfiles.profile(for: .openAICompatible, model: "gpt-6-luna")?.modelID, "gpt-6-luna")
  }

  func testDatedSnapshotsMatch() {
    XCTAssertEqual(
      ModelProfiles.profile(for: .openAICompatible, model: "gpt-6-luna-2026-09-01")?.modelID,
      "gpt-6-luna")
    XCTAssertEqual(
      ModelProfiles.profile(for: .anthropic, model: "claude-opus-4-5-20251101")?.modelID,
      "claude-opus-4-5")
  }

  func testNonDateSuffixDoesNotMatch() {
    XCTAssertNil(ModelProfiles.profile(for: .openAICompatible, model: "gpt-6-luna-mini"))
    XCTAssertNil(ModelProfiles.profile(for: .gemini, model: "gemini-3-flash-preview-x"))
    XCTAssertNil(ModelProfiles.profile(for: .openAICompatible, model: "gpt-6-luna-2026-13-01"))
    XCTAssertNil(ModelProfiles.profile(for: .openAICompatible, model: "gpt-6-lun"))
  }

  func testProfilesNeverCrossProviderKinds() {
    XCTAssertNil(ModelProfiles.profile(for: .anthropic, model: "gpt-6-luna"))
    XCTAssertNil(ModelProfiles.profile(for: .openAICompatible, model: "claude-haiku-5-5"))
    XCTAssertNil(ModelProfiles.profile(for: .ollama, model: "gemini-3.8-flash"))
  }

  func testModelsWithoutAProfile() {
    // research R3/R4: no effort support or nothing to change.
    XCTAssertNil(ModelProfiles.profile(for: .anthropic, model: "claude-haiku-4-5"))
    XCTAssertNil(ModelProfiles.profile(for: .gemini, model: "gemini-2.5-flash-lite"))
    XCTAssertNil(ModelProfiles.profile(for: .openAICompatible, model: "gpt-4o-mini"))
  }

  // MARK: - Table content (contracts/model-profiles.md)

  // Verified against Chat Completions 2026-10-17: no GPT-6 model accepts `max`
  // there, although the model pages list it.
  private let allLevelsOpenAI = ["none", "low", "medium", "high", "xhigh"]
  private let noNoneOpenAI = ["low", "medium", "high", "xhigh"]
  private let fullAnthropic = ["low", "medium", "high", "xhigh", "max"]
  private let noXhighAnthropic = ["low", "medium", "high", "max"]
  private let geminiWithMinimal = ["minimal", "low", "medium", "high"]
  private let geminiNoMinimal = ["low", "medium", "high"]

  private func assertLevels(
    _ kind: ProviderKind, _ model: String, _ supported: [String], preferred: String,
    temperature: TemperatureRule, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let profile = ModelProfiles.profile(for: kind, model: model) else {
      return XCTFail("missing profile \(model)", file: file, line: line)
    }
    XCTAssertEqual(
      profile.reasoning, .levels(supported: supported, preferred: preferred), model, file: file,
      line: line)
    XCTAssertEqual(profile.temperature, temperature, model, file: file, line: line)
    XCTAssertFalse(profile.source.isEmpty, model, file: file, line: line)
  }

  func testOpenAIProfiles() {
    assertLevels(
      .openAICompatible, "gpt-6-luna", allLevelsOpenAI, preferred: "none",
      temperature: .acceptedOnlyAtLevels(["none"]))
    assertLevels(
      .openAICompatible, "gpt-6-sol", allLevelsOpenAI, preferred: "none",
      temperature: .acceptedOnlyAtLevels(["none"]))
    assertLevels(
      .openAICompatible, "gpt-6-astra", noNoneOpenAI, preferred: "low", temperature: .rejected)
    assertLevels(
      .openAICompatible, "gpt-6.1-sol", noNoneOpenAI, preferred: "low", temperature: .rejected)
  }

  func testAnthropicProfiles() {
    for model in [
      "claude-fable-5-1", "claude-mythos-5-1", "claude-fable-5", "claude-mythos-5",
      "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
      "claude-sonnet-5-5", "claude-sonnet-5", "claude-haiku-5-5",
    ] {
      assertLevels(.anthropic, model, fullAnthropic, preferred: "low", temperature: .rejected)
    }
    for model in ["claude-mythos-preview", "claude-opus-4-6", "claude-sonnet-4-6"] {
      assertLevels(.anthropic, model, noXhighAnthropic, preferred: "low", temperature: .rejected)
    }
    assertLevels(
      .anthropic, "claude-opus-4-5", ["low", "medium", "high"], preferred: "low",
      temperature: .rejected)
  }

  func testGeminiLevelProfiles() {
    for model in ["gemini-4-argon", "gemini-3.8-flash", "gemini-3.7-flash"] {
      assertLevels(.gemini, model, geminiNoMinimal, preferred: "low", temperature: .discouraged)
    }
    for model in [
      "gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite",
      "gemini-3-flash-preview",
    ] {
      assertLevels(
        .gemini, model, geminiWithMinimal, preferred: "minimal", temperature: .discouraged)
    }
  }

  func testGeminiProfilesWithoutLevels() {
    let pro = ModelProfiles.profile(for: .gemini, model: "gemini-3.1-pro-preview")
    XCTAssertNil(pro?.reasoning)
    XCTAssertEqual(pro?.temperature, .discouraged)

    XCTAssertEqual(
      ModelProfiles.profile(for: .gemini, model: "gemini-2.5-pro")?.reasoning,
      .thinkingBudget(range: 128...32768, preferred: 128))
    XCTAssertEqual(
      ModelProfiles.profile(for: .gemini, model: "gemini-2.5-flash")?.reasoning,
      .thinkingBudget(range: 0...24576, preferred: 0))
    XCTAssertEqual(
      ModelProfiles.profile(for: .gemini, model: "gemini-2.5-flash")?.temperature, .accepted)
  }

  func testEveryPreferredValueIsSupported() {
    for profile in ModelProfiles.all {
      switch profile.reasoning {
      case .levels(let supported, let preferred):
        XCTAssertTrue(supported.contains(preferred), profile.modelID)
      case .thinkingBudget(let range, let preferred):
        XCTAssertTrue(range.contains(preferred), profile.modelID)
      case nil:
        break
      }
    }
  }

  func testProfileIDsAreUniquePerKind() {
    let keys = ModelProfiles.all.map { "\($0.kind.rawValue)/\($0.modelID)" }
    XCTAssertEqual(keys.count, Set(keys).count)
  }

  // MARK: - Editor value lists (FR-022)

  func testEditorReasoningValuesPerKind() {
    XCTAssertEqual(
      ModelProfiles.reasoningValues[.openAICompatible],
      ["none", "minimal", "low", "medium", "high", "xhigh", "max"])
    XCTAssertEqual(ModelProfiles.reasoningValues[.anthropic], fullAnthropic)
    XCTAssertEqual(ModelProfiles.reasoningValues[.gemini], geminiWithMinimal)
    XCTAssertNil(ModelProfiles.reasoningValues[.ollama])
  }
}
