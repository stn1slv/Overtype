import XCTest

@testable import Overtype

/// H6: the truncation threshold was computed from the TRAINED window, while the
/// request pins num_ctx to 16384; for any model trained above twice the request
/// the threshold sat above every possible prompt_eval_count and the guard was
/// inert. The effective window is the smaller of the two.
final class OllamaEffectiveWindowTests: XCTestCase {

  func testEffectiveWindowClampsLargeTrainedWindows() {
    XCTAssertEqual(OllamaProvider.effectiveWindow(reported: 40960), 16384)
    XCTAssertEqual(OllamaProvider.effectiveWindow(reported: 131_072), 16384)
  }

  func testEffectiveWindowKeepsSmallTrainedWindows() {
    XCTAssertEqual(OllamaProvider.effectiveWindow(reported: 2048), 2048)
    XCTAssertEqual(OllamaProvider.effectiveWindow(reported: 16384), 16384)
  }

  func testTruncationThresholdReachableForLargeModels() {
    // qwen3-class model trained at 40960: threshold must be half the EFFECTIVE
    // window (8192), a value prompt_eval_count can actually report.
    let threshold = OllamaProvider.truncationThreshold(
      grantedWindow: OllamaProvider.effectiveWindow(reported: 40960))
    XCTAssertEqual(threshold, 8192)

    let hugeModel = OllamaProvider.truncationThreshold(
      grantedWindow: OllamaProvider.effectiveWindow(reported: 131_072))
    XCTAssertEqual(hugeModel, 8192)
  }
}

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
    let text = String(repeating: "a", count: OllamaProvider.maxSafePromptTokens)
    XCTAssertNoThrow(try OllamaProvider.checkInputSize(systemPrompt: "", userPrompt: text))
  }

  func testTheSystemPromptCountsTowardTheLimit() {
    // The bound must measure what is sent. A selection just under the limit
    // plus a long system prompt still overflows the window.
    let userPrompt = String(repeating: "a", count: OllamaProvider.maxSafePromptTokens - 10)
    XCTAssertThrowsError(
      try OllamaProvider.checkInputSize(
        systemPrompt: String(repeating: "s", count: 100), userPrompt: userPrompt))
  }

  func testATemplateRepeatingTheSelectionCountsTwice() {
    // `{{text}}` is replaced at every occurrence, so a template naming it twice
    // doubles the input. Measuring the rendered prompt catches that; measuring
    // the selection would not.
    let selection = String(repeating: "a", count: 4000)
    let rendered = "\(selection)\n\n\(selection)"
    XCTAssertThrowsError(
      try OllamaProvider.checkInputSize(systemPrompt: "", userPrompt: rendered))
  }

  func testInputAboveTheLimitIsRefusedWithTheLimitAttached() {
    let text = String(repeating: "a", count: OllamaProvider.maxSafePromptTokens + 1)
    do {
      try OllamaProvider.checkInputSize(systemPrompt: "", userPrompt: text)
      XCTFail("expected an oversized selection to be refused")
    } catch let error as ProviderError {
      guard case .inputTooLargeForContext(let limit) = error else {
        return XCTFail("expected inputTooLargeForContext, got \(error)")
      }
      XCTAssertEqual(limit, OllamaProvider.maxSafePromptTokens)
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
    let worstCaseInputTokens = OllamaProvider.maxSafePromptTokens
    let worstCaseAnswerTokens = OllamaProvider.maxSafePromptTokens
    let systemPromptAllowance = 512

    XCTAssertLessThanOrEqual(
      worstCaseInputTokens + worstCaseAnswerTokens + systemPromptAllowance,
      OllamaProvider.contextWindowTokens,
      "a maximum-length selection and its rewrite must fit the context window "
        + "even at one token per character, or the service silently truncates the prompt")
  }

  func testTheSizeBoundNeverRefusesASelectionTheDefaultActionCapAllows() {
    // Drives the guard rather than comparing two constants: the previous
    // version asserted `maxSafePromptTokens >= defaultCap` and so would have
    // passed even when the shipped guard refused a default-cap selection,
    // because the system prompt also counts toward the budget.
    let defaultCap = ActionConfig(
      id: "t", title: "t", enabled: true, providerID: "p", systemPrompt: "",
      userPromptTemplate: "{{text}}"
    ).maxInputCharacters

    // The system prompt actually shipped, read from the default configuration
    // rather than copied, so a longer default prompt fails this test.
    guard
      let shipped = try? JSONDecoder().decode(
        AppConfig.self, from: Data(DefaultConfig.defaultConfigJSON.utf8)),
      let action = shipped.actions.first
    else {
      return XCTFail("could not read the shipped default configuration")
    }

    XCTAssertNoThrow(
      try OllamaProvider.checkInputSize(
        systemPrompt: action.systemPrompt,
        userPrompt: String(repeating: "a", count: defaultCap)),
      "a full default-cap selection must not be refused with the shipped system prompt")
  }

  func testALongSystemPromptEatsIntoTheSelectionAllowance() {
    // Documents the real relationship rather than pretending it does not exist:
    // the budget is shared, so a long system prompt lowers what is left for the
    // selection. The README says so; this pins it.
    let longSystemPrompt = String(repeating: "s", count: 2000)
    XCTAssertThrowsError(
      try OllamaProvider.checkInputSize(
        systemPrompt: longSystemPrompt,
        userPrompt: String(repeating: "a", count: 5000)))
  }

  // MARK: - estimatedTokens

  func testAsciiIsEstimatedByCharacterCount() {
    XCTAssertEqual(OllamaProvider.estimatedTokens(String(repeating: "a", count: 100)), 100)
  }

  func testCJKIsEstimatedByItsByteCost() {
    // Measured against the real service: 100 randomly chosen CJK characters
    // (300 bytes) were reported as 328 evaluated tokens, i.e. roughly one token
    // per BYTE via tokenizer byte-fallback — not one per character. The estimate
    // must therefore count bytes, or it understates these by 3x in the direction
    // that loses the user's text.
    let cjk = String(repeating: "\u{732B}", count: 100)
    XCTAssertEqual(cjk.utf8.count, 300)
    XCTAssertEqual(OllamaProvider.estimatedTokens(cjk), 300)
  }

  func testTheOverheadReserveCoversTheMeasuredTemplateCost() {
    // The estimate counts only the text, but the server also prepends chat
    // template and special tokens. Measured on Ollama 0.32.5: 300 bytes of CJK
    // evaluated to 328 tokens, 1200 bytes to 1194 — an overhead of roughly +30
    // that `estimatedTokens` structurally cannot see. The reserve must cover it,
    // or the budget and the truncation signal overlap.
    let measuredOverhead = 328 - 300
    XCTAssertGreaterThan(
      OllamaProvider.templateOverheadTokens, measuredOverhead,
      "the reserve must exceed the measured template overhead, or a legitimate "
        + "near-budget prompt is indistinguishable from a truncated one")
  }

  func testALegitimatePromptCanNeverReachTheTruncationSignal() {
    // The property the whole design turns on, asserted rather than argued: a
    // prompt that passes the pre-send check, plus the worst-case template
    // overhead, must still evaluate below the count that means "truncated".
    for window in [2048, 4096, 8192, 16384, 131_072] {
      let budget = OllamaProvider.promptBudget(grantedWindow: window)
      let signal = OllamaProvider.truncationThreshold(grantedWindow: window)
      XCTAssertLessThan(
        budget + OllamaProvider.templateOverheadTokens, signal,
        "at window \(window) a legitimate prompt could be misread as truncated")
    }
  }

  // MARK: - promptBudget

  func testBudgetIsHalfTheWindowLessTheReserveWhenTheWindowIsSmall() {
    // Measured: a model with a 2048 window keeps ~1026 prompt tokens when it
    // truncates, i.e. half. The budget follows the window, minus the reserve
    // that keeps a legitimate prompt clear of that signal.
    XCTAssertEqual(
      OllamaProvider.promptBudget(grantedWindow: 2048),
      1024 - OllamaProvider.templateOverheadTokens * 2)
    XCTAssertEqual(
      OllamaProvider.promptBudget(grantedWindow: 4096),
      2048 - OllamaProvider.templateOverheadTokens * 2)
  }

  func testAnUnknownWindowFailsClosedRatherThanFallingBackToTheFixedConstant() {
    // The regression this guards: falling back to `maxSafePromptTokens` when the
    // window is unknown re-created the silent-truncation hole for any deployment
    // that does not expose /api/show.
    let unknown = OllamaProvider.promptBudget(grantedWindow: nil)
    XCTAssertLessThan(
      unknown, OllamaProvider.maxSafePromptTokens,
      "an unknown window must not grant the full fixed budget")
    XCTAssertEqual(
      unknown,
      OllamaProvider.assumedWindowWhenUnknown / 2 - OllamaProvider.templateOverheadTokens * 2)
  }

  func testTheSmallestContextLengthWins() {
    // Dictionary order is unspecified, so a body with two matching keys must not
    // yield a different window on different launches.
    let body = Data(
      #"{"model_info":{"llama.context_length":8192,"clip.context_length":2048}}"#.utf8)
    XCTAssertEqual(OllamaProvider.parseContextLength(from: body), 2048)
  }

  func testTheReportedLimitIsTheBudgetInForceNotTheFixedConstant() {
    // On a small-window model the two differ, and naming 6000 when the run was
    // refused at 896 aims the user at the wrong number.
    do {
      try OllamaProvider.checkInputSize(
        systemPrompt: "", userPrompt: String(repeating: "a", count: 2000), budgetTokens: 896)
      XCTFail("expected a refusal")
    } catch let error as ProviderError {
      guard case .inputTooLargeForContext(let limit) = error else {
        return XCTFail("expected inputTooLargeForContext, got \(error)")
      }
      XCTAssertEqual(limit, 896)
    } catch {
      XCTFail("unexpected: \(error)")
    }
  }

  func testBudgetIsCappedByTheFixedConstantForLargeWindows() {
    XCTAssertEqual(
      OllamaProvider.promptBudget(grantedWindow: 131_072), OllamaProvider.maxSafePromptTokens)
    XCTAssertEqual(
      OllamaProvider.promptBudget(grantedWindow: 16384), OllamaProvider.maxSafePromptTokens)
  }

  func testASmallWindowModelRefusesAPromptTheFixedConstantWouldAllow() {
    // The hole the granted-window lookup closes: 3000 bytes passes the fixed
    // 6000 budget, but a 2048-window model only keeps ~1024 prompt tokens.
    let text = String(repeating: "a", count: 3000)
    XCTAssertNoThrow(try OllamaProvider.checkInputSize(systemPrompt: "", userPrompt: text))
    XCTAssertThrowsError(
      try OllamaProvider.checkInputSize(
        systemPrompt: "", userPrompt: text,
        budgetTokens: OllamaProvider.promptBudget(grantedWindow: 2048)))
  }

  func testGraphemeClustersAreNotCountedAsOneToken() {
    // The hole this estimate closes: `count` is 1 for a 25-byte cluster, so a
    // character count would wave 6000 of these straight past the guard.
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
    XCTAssertEqual(family.count, 1)
    XCTAssertGreaterThan(OllamaProvider.estimatedTokens(family), 1)
  }

  func testAnEmojiSelectionUnderTheCharacterCountIsStillRefused() {
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
    let selection = String(repeating: family, count: 3000)
    XCTAssertEqual(selection.count, 3000, "well under the 6000 bound by character count")
    XCTAssertThrowsError(
      try OllamaProvider.checkInputSize(systemPrompt: "", userPrompt: selection),
      "a selection of multi-byte clusters must be refused, not silently truncated by the service")
  }

  func testCombiningMarksAreCountedHonestly() {
    // One base letter plus 50 combining acutes: `count` is 1, 101 UTF-8 bytes.
    let stacked = "a" + String(repeating: "\u{0301}", count: 50)
    XCTAssertEqual(stacked.count, 1)
    XCTAssertGreaterThan(OllamaProvider.estimatedTokens(stacked), 1)
  }

  // MARK: - Granted context window (/api/show)

  func testShowEndpointIsBuiltFromTheSameBase() throws {
    XCTAssertEqual(
      try OllamaProvider.showEndpointURL(base: nil).absoluteString,
      "http://localhost:11434/api/show")
    XCTAssertEqual(
      try OllamaProvider.showEndpointURL(base: URL(string: "http://box:9999/")).absoluteString,
      "http://box:9999/api/show")
  }

  func testContextLengthIsReadRegardlessOfArchitecturePrefix() {
    for arch in ["llama", "qwen2", "gemma3", "some.future.arch"] {
      let body = Data("{\"model_info\":{\"\(arch).context_length\":4096}}".utf8)
      XCTAssertEqual(
        OllamaProvider.parseContextLength(from: body), 4096,
        "the key is architecture-prefixed; matching by suffix must not go stale")
    }
  }

  func testMissingOrUnusableContextLengthIsNil() {
    XCTAssertNil(OllamaProvider.parseContextLength(from: Data("{}".utf8)))
    XCTAssertNil(OllamaProvider.parseContextLength(from: Data("not json".utf8)))
    XCTAssertNil(
      OllamaProvider.parseContextLength(from: Data(#"{"model_info":{"llama.embedding":1}}"#.utf8)))
    XCTAssertNil(
      OllamaProvider.parseContextLength(
        from: Data(#"{"model_info":{"llama.context_length":0}}"#.utf8)))
  }

  func testTruncationIsDetectedAtTheGrantedWindowNotTheRequestedOne() {
    // The hole this closes: Ollama clamps num_ctx down to the model's own
    // maximum, so a model built at 4096 runs at 4096 however much we ask for.
    // Comparing against the requested 16384 would leave the check dead for
    // exactly the models that truncate.
    let json: [String: Any] = [
      "message": ["role": "assistant", "content": "a partial rewrite"],
      "done": true,
      "prompt_eval_count": 4096,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: json) else {
      return XCTFail("bad fixture")
    }

    // Against the requested window this looks fine — and that was the bug.
    XCTAssertEqual(
      try? OllamaProvider.parseResponseText(
        from: data, truncationThreshold: OllamaProvider.contextWindowTokens),
      "a partial rewrite")

    // Against the budget the service actually granted, it is a truncation.
    XCTAssertThrowsError(
      try OllamaProvider.parseResponseText(
        from: data, truncationThreshold: 1024, reportedLimit: 768)
    ) { error in
      guard case ProviderError.inputTooLargeForContext = error else {
        return XCTFail("expected inputTooLargeForContext, got \(error)")
      }
    }
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

  func testReasoningWithNoOpeningMarkerIsRemoved() {
    // The DeepSeek-R1 shape: the chat template puts `<think>` in the PROMPT, so
    // the completion starts with bare reasoning and ends with a lone closing
    // marker. Without this rule the reasoning is typed into the document.
    let result = OllamaProvider.stripLeadingReasoningBlock(
      "Okay, the subject is singular so the verb must be singular.\n</think>\nThe cat is sleeping.")
    XCTAssertEqual(result, "The cat is sleeping.")
  }

  func testOrphanClosingMarkerWithNoAnswerYieldsEmpty() {
    XCTAssertEqual(OllamaProvider.stripLeadingReasoningBlock("reasoning only</think>"), "")
  }

  func testAPairedBlockMidTextIsStillLeftAlone() {
    // The orphan rule must not fire when an opening marker precedes the closing
    // one, or it would eat legitimate text the user asked to have rewritten.
    let text = "Use the <think> tag to mark reasoning.</think> That is the convention."
    XCTAssertEqual(OllamaProvider.stripLeadingReasoningBlock(text), text)
  }

  func testNestedBlocksLeaveNoResidue() {
    // The inner closing marker ends the outer block, leaving `tail</think>...`,
    // which the orphan rule then clears.
    let result = OllamaProvider.stripLeadingReasoningBlock(
      "<think>outer <think>inner</think> tail</think>Answer.")
    XCTAssertEqual(result, "Answer.")
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

  func testATruncatedPromptIsDetectedAndRefused() {
    // prompt_eval_count at the window means the service clipped the prompt, so
    // the answer was produced from part of the selection only. Writing it would
    // overwrite the whole selection with a rewrite of a fragment.
    var json: [String: Any] = [
      "model": "llama3.2",
      "message": ["role": "assistant", "content": "a partial rewrite"],
      "done": true,
      "prompt_eval_count": OllamaProvider.contextWindowTokens,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: json) else {
      return XCTFail("bad fixture")
    }
    XCTAssertThrowsError(
      try OllamaProvider.parseResponseText(
        from: data, truncationThreshold: OllamaProvider.contextWindowTokens - 1)
    ) { error in
      guard case ProviderError.inputTooLargeForContext = error else {
        return XCTFail("expected inputTooLargeForContext, got \(error)")
      }
    }

    // A normal count is not refused.
    json["prompt_eval_count"] = 42
    guard let ok = try? JSONSerialization.data(withJSONObject: json) else {
      return XCTFail("bad fixture")
    }
    XCTAssertEqual(try? OllamaProvider.parseResponseText(from: ok), "a partial rewrite")
  }

  func testAbsentPromptEvalCountIsNotTreatedAsTruncation() {
    let data = responseData(["role": "assistant", "content": "The cat is sleeping."])
    XCTAssertEqual(try? OllamaProvider.parseResponseText(from: data), "The cat is sleeping.")
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
    do {
      try KeychainStore.shared.store(key: key, value: "secret-token")
    } catch {
      // The login keychain may be locked or absent (unattended CI). Skip rather
      // than fail: the constitution treats the Keychain as system-boundary work
      // verified by manual acceptance, so this test is a local convenience, not
      // a gate.
      throw XCTSkip("Keychain unavailable in this environment: \(error)")
    }
    defer { try? KeychainStore.shared.delete(key: key) }

    XCTAssertEqual(
      OllamaProvider.authorizationHeader(forKeychainKey: key), "Bearer secret-token")
  }
}
