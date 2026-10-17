import XCTest

@testable import Overtype

/// specs/010-model-aware-parameters: one pure resolver decides what each
/// request carries. `ActionEngine.run` and the Actions editor both call it, so
/// these cases also define what the editor caption and warnings show.
final class GenerationParameterResolverTests: XCTestCase {

  private func resolve(
    _ kind: ProviderKind, _ model: String, temperature: Double? = nil, reasoning: String? = nil,
    learned: Set<DroppableParameter> = []
  ) -> ResolvedGenerationParameters {
    GenerationParameterResolver.resolve(
      kind: kind, model: model, temperatureOverride: temperature, reasoningOverride: reasoning,
      learnedRejections: learned)
  }

  // MARK: - Automatic

  func testAutomaticUsesTheProfilesPreferredValue() {
    XCTAssertEqual(resolve(.openAICompatible, "gpt-6-luna").reasoning, .level("none"))
    XCTAssertEqual(resolve(.openAICompatible, "gpt-6.1-sol").reasoning, .level("low"))
    XCTAssertEqual(resolve(.anthropic, "claude-haiku-5-5").reasoning, .level("low"))
    XCTAssertEqual(resolve(.gemini, "gemini-3.8-flash").reasoning, .level("low"))
    XCTAssertEqual(resolve(.gemini, "gemini-3.5-flash-lite").reasoning, .level("minimal"))
    XCTAssertEqual(resolve(.gemini, "gemini-2.5-flash").reasoning, .thinkingBudget(0))
  }

  func testAutomaticSendsNoTemperature() {
    let resolved = resolve(.openAICompatible, "gpt-6-luna")
    XCTAssertNil(resolved.temperature)
    XCTAssertTrue(resolved.withheldOverrides.isEmpty)
  }

  func testAutomaticCaptionReportsTheResolvedValue() {
    XCTAssertEqual(
      resolve(.openAICompatible, "gpt-6-luna", reasoning: "high").automaticReasoning,
      .level("none"))
    XCTAssertNil(resolve(.openAICompatible, "gpt-4o-mini").automaticReasoning)
    XCTAssertNil(resolve(.ollama, "llama3.2").automaticReasoning)
  }

  // MARK: - Overrides

  func testOverrideWinsOverThePreference() {
    XCTAssertEqual(
      resolve(.openAICompatible, "gpt-6-luna", reasoning: "high").reasoning, .level("high"))
    XCTAssertEqual(resolve(.anthropic, "claude-opus-5", reasoning: "max").reasoning, .level("max"))
  }

  func testLunaKeepsTemperatureAtNone() {
    // The reported case: a stored temperature 0 on gpt-6-luna. Automatic picks
    // effort none, where the model accepts a temperature (research R1).
    let resolved = resolve(.openAICompatible, "gpt-6-luna", temperature: 0)
    XCTAssertEqual(resolved.reasoning, .level("none"))
    XCTAssertEqual(resolved.temperature, 0)
  }

  func testLunaWithholdsTemperatureAtOtherEfforts() {
    let resolved = resolve(.openAICompatible, "gpt-6-luna", temperature: 0, reasoning: "medium")
    XCTAssertNil(resolved.temperature)
    XCTAssertEqual(
      resolved.withheldOverrides,
      [WithheldOverride(parameter: .temperature, reason: .modelRejects)])
  }

  func testModelThatNeverTakesTemperature() {
    let resolved = resolve(.openAICompatible, "gpt-6-astra", temperature: 0.7)
    XCTAssertNil(resolved.temperature)
    XCTAssertEqual(
      resolved.withheldOverrides,
      [WithheldOverride(parameter: .temperature, reason: .modelRejects)])
  }

  func testGeminiThreeWithholdsTemperature() {
    for model in ["gemini-3.8-flash", "gemini-4-argon", "gemini-3.1-pro-preview"] {
      let resolved = resolve(.gemini, model, temperature: 0)
      XCTAssertNil(resolved.temperature, model)
      XCTAssertEqual(
        resolved.withheldOverrides,
        [WithheldOverride(parameter: .temperature, reason: .providerSaysRemove)], model)
    }
  }

  func testGeminiTwoPointFiveKeepsTemperature() {
    XCTAssertEqual(resolve(.gemini, "gemini-2.5-flash", temperature: 0.3).temperature, 0.3)
  }

  func testUnsupportedOverrideFallsBackToAutomatic() {
    let resolved = resolve(.gemini, "gemini-3.8-flash", reasoning: "minimal")
    XCTAssertEqual(resolved.reasoning, .level("low"))
    XCTAssertEqual(
      resolved.withheldOverrides,
      [WithheldOverride(parameter: .reasoning, reason: .unsupportedValue)])
  }

  func testTextOverrideOnABudgetModelIsUnsupported() {
    let resolved = resolve(.gemini, "gemini-2.5-pro", reasoning: "low")
    XCTAssertEqual(resolved.reasoning, .thinkingBudget(128))
    XCTAssertEqual(
      resolved.withheldOverrides,
      [WithheldOverride(parameter: .reasoning, reason: .unsupportedValue)])
  }

  // MARK: - Models without a profile (SC-004)

  func testUnprofiledModelPassesOverridesThrough() {
    let resolved = resolve(.openAICompatible, "gpt-4o-mini", temperature: 0, reasoning: "low")
    XCTAssertEqual(resolved.temperature, 0)
    XCTAssertEqual(resolved.reasoning, .level("low"))
    XCTAssertTrue(resolved.withheldOverrides.isEmpty)
  }

  func testUnprofiledModelOnAutomaticSendsNothingOptional() {
    let resolved = resolve(.gemini, "gemini-flash-latest")
    XCTAssertNil(resolved.temperature)
    XCTAssertNil(resolved.reasoning)
  }

  // MARK: - Provider-wide rules

  func testAnthropicNeverGetsATemperature() {
    for model in ["claude-haiku-5-5", "claude-haiku-4-5"] {
      let resolved = resolve(.anthropic, model, temperature: 0.5)
      XCTAssertNil(resolved.temperature, model)
      XCTAssertEqual(
        resolved.withheldOverrides,
        [WithheldOverride(parameter: .temperature, reason: .providerIgnores)], model)
    }
  }

  func testOllamaNeverGetsAReasoningValue() {
    let resolved = resolve(.ollama, "llama3.2", temperature: 0.2, reasoning: "low")
    XCTAssertNil(resolved.reasoning)
    XCTAssertEqual(resolved.temperature, 0.2)
    XCTAssertEqual(
      resolved.withheldOverrides,
      [WithheldOverride(parameter: .reasoning, reason: .providerIgnores)])
  }

  // MARK: - Learned rejections (US3)

  func testLearnedRejectionsAreWithheld() {
    let resolved = resolve(
      .openAICompatible, "gpt-4o-mini", temperature: 0, reasoning: "low",
      learned: [.temperature, .reasoning])
    XCTAssertNil(resolved.temperature)
    XCTAssertNil(resolved.reasoning)
    XCTAssertEqual(
      resolved.withheldOverrides,
      [
        WithheldOverride(parameter: .reasoning, reason: .learnedRejection),
        WithheldOverride(parameter: .temperature, reason: .learnedRejection),
      ])
  }

  func testLearnedReasoningRejectionAlsoDropsTheAutomaticValue() {
    let resolved = resolve(.openAICompatible, "gpt-6-luna", learned: [.reasoning])
    XCTAssertNil(resolved.reasoning)
    XCTAssertTrue(resolved.withheldOverrides.isEmpty)
  }

  func testRejectionMemoryIsIsolatedPerProviderBaseURLAndModel() {
    let memory = ParameterRejectionMemory()
    let key = ParameterRejectionMemory.Key(
      providerID: "openai", baseURL: "https://api.openai.com/v1", model: "gpt-x")
    memory.record(.temperature, for: key)
    memory.record(.temperature, for: key)

    XCTAssertEqual(memory.rejections(for: key), [.temperature])
    XCTAssertTrue(
      memory.rejections(
        for: .init(providerID: "openai", baseURL: "https://api.openai.com/v1", model: "gpt-y")
      ).isEmpty)
    XCTAssertTrue(
      memory.rejections(
        for: .init(providerID: "openai", baseURL: "https://proxy.example/v1", model: "gpt-x")
      ).isEmpty)
    XCTAssertTrue(
      memory.rejections(
        for: .init(providerID: "other", baseURL: "https://api.openai.com/v1", model: "gpt-x")
      ).isEmpty)
  }

  // MARK: - TransformRequest.removing

  func testRemovingDropsOnlyTheNamedParameter() throws {
    let request = TransformRequest(
      text: "t", systemPrompt: "s", userPromptTemplate: "{{text}}", model: "m", temperature: 0,
      reasoning: .level("none"))
    let withoutTemperature = try XCTUnwrap(request.removing(.temperature))
    XCTAssertNil(withoutTemperature.temperature)
    XCTAssertEqual(withoutTemperature.reasoning, .level("none"))
    let withoutReasoning = try XCTUnwrap(request.removing(.reasoning))
    XCTAssertEqual(withoutReasoning.temperature, 0)
    XCTAssertNil(withoutReasoning.reasoning)
  }

  func testRemovingAParameterTheRequestLacksReturnsNil() {
    let request = TransformRequest(
      text: "t", systemPrompt: "s", userPromptTemplate: "{{text}}", model: "m", temperature: nil)
    XCTAssertNil(request.removing(.temperature))
    XCTAssertNil(request.removing(.reasoning))
  }
}
