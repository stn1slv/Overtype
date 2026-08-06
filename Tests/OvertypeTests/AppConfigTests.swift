import XCTest

@testable import Overtype

final class AppConfigTests: XCTestCase {

  func testDefaultConfigJSONDecodesCorrectly() {
    let json = DefaultConfig.defaultConfigJSON
    guard let data = json.data(using: .utf8) else {
      XCTFail("Failed to convert default config JSON to data")
      return
    }

    do {
      let config = try JSONDecoder().decode(AppConfig.self, from: data)
      XCTAssertEqual(config.global.showHUD, true)
      XCTAssertEqual(config.global.typingSpeedMultiplier, 1.0)
      XCTAssertEqual(config.providers.count, 1)
      XCTAssertEqual(config.providers[0].id, "openai")
      XCTAssertEqual(config.actions.count, 1)
      XCTAssertEqual(config.actions[0].id, "fix-grammar")
    } catch {
      XCTFail("Failed to decode AppConfig: \(error)")
    }
  }

  func testGeminiProviderConfigDecodes() {
    let json = #"""
      {
        "id": "gemini",
        "kind": "gemini",
        "defaultModel": "gemini-3.5-flash-lite",
        "timeoutSeconds": 30,
        "keychainKey": "gemini-api-key"
      }
      """#
    guard let data = json.data(using: .utf8) else {
      XCTFail("Failed to convert Gemini provider JSON to data")
      return
    }

    do {
      let provider = try JSONDecoder().decode(ProviderConfig.self, from: data)
      XCTAssertEqual(provider.kind, .gemini)
      XCTAssertEqual(provider.id, "gemini")
      XCTAssertEqual(provider.defaultModel, "gemini-3.5-flash-lite")
      XCTAssertEqual(provider.keychainKey, "gemini-api-key")
    } catch {
      XCTFail("Failed to decode Gemini ProviderConfig: \(error)")
    }
  }

  func testAnthropicProviderConfigDecodes() {
    let json = #"""
      {
        "id": "anthropic",
        "kind": "anthropic",
        "defaultModel": "claude-haiku-4-5",
        "timeoutSeconds": 30,
        "keychainKey": "overtype-anthropic-key"
      }
      """#
    guard let data = json.data(using: .utf8) else {
      XCTFail("Failed to convert Anthropic provider JSON to data")
      return
    }

    do {
      let provider = try JSONDecoder().decode(ProviderConfig.self, from: data)
      XCTAssertEqual(provider.kind, .anthropic)
      XCTAssertEqual(provider.id, "anthropic")
      XCTAssertEqual(provider.defaultModel, "claude-haiku-4-5")
      XCTAssertEqual(provider.keychainKey, "overtype-anthropic-key")
    } catch {
      XCTFail("Failed to decode Anthropic ProviderConfig: \(error)")
    }
  }

  func testOllamaProviderConfigDecodesWithoutBaseURLOrKeychainKey() throws {
    // The documented recipe: no endpoint (the provider falls back to the local
    // default) and no credential (a local service needs none). Both omissions
    // must decode to nil rather than failing, because that is the normal
    // configuration for this kind, not a degenerate one.
    let json = #"""
      {
        "id": "ollama-local",
        "kind": "ollama",
        "defaultModel": "llama3.2",
        "timeoutSeconds": 30
      }
      """#

    let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertEqual(provider.kind, .ollama)
    XCTAssertEqual(provider.id, "ollama-local")
    XCTAssertEqual(provider.defaultModel, "llama3.2")
    XCTAssertEqual(provider.timeoutSeconds, 30.0)
    XCTAssertNil(provider.baseURL)
    XCTAssertNil(provider.keychainKey)
  }

  func testOllamaProviderConfigRoundTrips() throws {
    let original = ProviderConfig(
      id: "ollama-local", kind: .ollama, defaultModel: "llama3.2", timeoutSeconds: 30)
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ProviderConfig.self, from: encoded)
    XCTAssertEqual(decoded, original)
  }

  // MARK: - Tolerant decoding (missing keys fall back to defaults instead of
  // failing the whole config decode)

  func testProviderConfigDecodesWithoutTimeoutSeconds() throws {
    let json = #"{"id": "p1", "kind": "openai", "defaultModel": "gpt-4o"}"#
    let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertEqual(provider.timeoutSeconds, 30.0)
    XCTAssertNil(provider.baseURL)
    XCTAssertNil(provider.keychainKey)
  }

  func testProviderConfigDecodesWithoutRetryDelaySeconds() throws {
    // Configs written before the retry feature have no such key; they must keep
    // decoding and fall back to the 0.5s default.
    let json = #"{"id": "p1", "kind": "openai", "defaultModel": "gpt-4o"}"#
    let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertEqual(provider.retryDelaySeconds, 0.5)
  }

  func testProviderConfigDecodesExplicitRetryDelaySeconds() throws {
    let json = #"""
      {"id": "p1", "kind": "openai", "defaultModel": "gpt-4o", "retryDelaySeconds": 2.5}
      """#
    let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertEqual(provider.retryDelaySeconds, 2.5)
  }

  func testProviderConfigDecodesZeroRetryDelayAsZero() throws {
    // 0 means "retry immediately" and must survive decoding rather than being
    // treated as a missing value and replaced by the default.
    let json = #"{"id": "p1", "kind": "openai", "defaultModel": "gpt-4o", "retryDelaySeconds": 0}"#
    let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertEqual(provider.retryDelaySeconds, 0)
  }

  func testActionConfigDecodesWithOnlyRequiredFields() throws {
    let json = #"""
      {
        "id": "a1",
        "title": "Test",
        "providerID": "p1",
        "systemPrompt": "sys",
        "userPromptTemplate": "{{text}}"
      }
      """#
    let action = try JSONDecoder().decode(ActionConfig.self, from: Data(json.utf8))
    XCTAssertTrue(action.enabled)
    XCTAssertNil(action.shortcut)
    XCTAssertNil(action.model)
    XCTAssertEqual(action.temperature, 0.0)
    XCTAssertEqual(action.maxInputCharacters, 5000)
    XCTAssertFalse(action.allowNewlines)
    XCTAssertEqual(action.writeStrategy, .typing)
  }

  func testGeneralConfigDecodesFromEmptyObject() throws {
    let general = try JSONDecoder().decode(GeneralConfig.self, from: Data("{}".utf8))
    XCTAssertEqual(general.typingSpeedMultiplier, 1.0)
    XCTAssertTrue(general.showHUD)
    XCTAssertNil(general.typingChunkSize)
    XCTAssertNil(general.typingDelayMicroseconds)
    XCTAssertNil(general.appTypingOverrides)
  }

  func testAppConfigDecodesWithMissingSections() throws {
    let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
    XCTAssertEqual(config.global, GeneralConfig())
    XCTAssertTrue(config.providers.isEmpty)
    XCTAssertTrue(config.actions.isEmpty)
  }

  func testActionConfigMissingRequiredFieldStillFails() {
    // Identity and prompts stay required: an action without them is unusable.
    let json = #"{"id": "a1", "title": "Test", "providerID": "p1"}"#
    XCTAssertThrowsError(try JSONDecoder().decode(ActionConfig.self, from: Data(json.utf8)))
  }

  func testAppConfigRoundTripEncoding() {
    let original = AppConfig(
      global: GeneralConfig(
        typingSpeedMultiplier: 1.5, showHUD: false, typingChunkSize: 10,
        typingDelayMicroseconds: 5000),
      providers: [
        ProviderConfig(
          id: "openai-test", kind: .openAICompatible,
          baseURL: URL(string: "https://example.com/v1"), defaultModel: "gpt-4",
          timeoutSeconds: 10.0, keychainKey: "test-key")
      ],
      actions: [
        ActionConfig(
          id: "test-action", title: "Test Action", enabled: true, providerID: "openai-test",
          systemPrompt: "Test System", userPromptTemplate: "{{text}}")
      ]
    )

    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(original)

      let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
      XCTAssertEqual(decoded, original)
    } catch {
      XCTFail("Failed to encode or decode AppConfig: \(error)")
    }
  }
}
