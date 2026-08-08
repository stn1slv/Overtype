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

  // MARK: - Shortcut validity (C1): config.json is a hand-editing surface, so a
  // negative keyCode/modifiers must yield an unusable-but-safe shortcut, never a
  // trap in UInt(_:) at registration time.

  func testShortcutWithNegativeModifiersYieldsNilKeyboardShortcut() throws {
    let json = #"{"keyCode": 5, "modifiers": -1, "displayString": "bad"}"#
    let shortcut = try JSONDecoder().decode(ActionShortcut.self, from: Data(json.utf8))
    XCTAssertNil(shortcut.keyboardShortcut)
  }

  func testShortcutWithNegativeKeyCodeYieldsNilKeyboardShortcut() throws {
    let json = #"{"keyCode": -7, "modifiers": 1835008, "displayString": "bad"}"#
    let shortcut = try JSONDecoder().decode(ActionShortcut.self, from: Data(json.utf8))
    XCTAssertNil(shortcut.keyboardShortcut)
  }

  func testValidShortcutYieldsKeyboardShortcut() throws {
    // 1835008 == 0x1C0000 == control+option+command; keyCode 5 == kVK_ANSI_G.
    // Matches the shipped default action's shortcut.
    let json = #"{"keyCode": 5, "modifiers": 1835008, "displayString": "⌃⌥⌘G"}"#
    let shortcut = try JSONDecoder().decode(ActionShortcut.self, from: Data(json.utf8))
    let keyboardShortcut = try XCTUnwrap(shortcut.keyboardShortcut)
    XCTAssertEqual(keyboardShortcut.modifiers.rawValue, UInt(1_835_008))
  }

  // MARK: - Type-tolerant decoding (C3): a wrong-typed value falls back per
  // field, and a broken array element is dropped alone. One bad value must
  // never cost the whole configuration.

  func testWrongTypedShowHUDFallsBackToDefault() throws {
    let json = #"{"global": {"showHUD": "true", "typingSpeedMultiplier": 2.0}}"#
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    XCTAssertTrue(config.global.showHUD)
    XCTAssertEqual(config.global.typingSpeedMultiplier, 2.0)
  }

  func testWrongTypedTemperatureFallsBackToDefault() throws {
    let json = #"""
      {
        "id": "a1", "title": "T", "providerID": "p1",
        "systemPrompt": "s", "userPromptTemplate": "{{text}}",
        "temperature": "hot"
      }
      """#
    let action = try JSONDecoder().decode(ActionConfig.self, from: Data(json.utf8))
    XCTAssertEqual(action.temperature, 0.0)
  }

  func testWrongTypedBaseURLFallsBackToNil() throws {
    let json = #"{"id": "p1", "kind": "openai", "defaultModel": "m", "baseURL": 12345}"#
    let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertNil(provider.baseURL)
  }

  func testEmptyBaseURLStringFallsBackToNil() throws {
    let json = #"{"id": "p1", "kind": "openai", "defaultModel": "m", "baseURL": ""}"#
    let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertNil(provider.baseURL)
  }

  func testUnknownProviderKindDropsOnlyThatElement() throws {
    let json = #"""
      {
        "providers": [
          {"id": "weird", "kind": "openrouter", "defaultModel": "m"},
          {"id": "good", "kind": "openai", "defaultModel": "gpt-4o"}
        ],
        "actions": [
          {"id": "a1", "title": "T", "providerID": "good",
           "systemPrompt": "s", "userPromptTemplate": "{{text}}"}
        ]
      }
      """#
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    XCTAssertEqual(config.providers.map(\.id), ["good"])
    XCTAssertEqual(config.actions.count, 1)
  }

  func testActionElementMissingRequiredFieldIsDroppedAlone() throws {
    let json = #"""
      {
        "actions": [
          {"id": "broken", "title": "T", "providerID": "p1"},
          {"id": "ok", "title": "T", "providerID": "p1",
           "systemPrompt": "s", "userPromptTemplate": "{{text}}"}
        ]
      }
      """#
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    XCTAssertEqual(config.actions.map(\.id), ["ok"])
  }

  func testShortcutMissingDisplayStringStillDecodes() throws {
    let json = #"""
      {
        "id": "a1", "title": "T", "providerID": "p1",
        "systemPrompt": "s", "userPromptTemplate": "{{text}}",
        "shortcut": {"keyCode": 5, "modifiers": 1835008}
      }
      """#
    let action = try JSONDecoder().decode(ActionConfig.self, from: Data(json.utf8))
    XCTAssertEqual(action.shortcut?.displayString, "")
    XCTAssertEqual(action.shortcut?.keyCode, 5)
  }

  func testDecodingIssuesAreCollectedAndNameKeysOnly() throws {
    let json = #"""
      {
        "global": {"showHUD": "yes"},
        "providers": [
          {"id": "weird", "kind": "openrouter", "defaultModel": "m"}
        ]
      }
      """#
    let issues = ConfigDecodingIssues()
    let decoder = JSONDecoder()
    ConfigDecodingIssues.attach(issues, to: decoder)
    _ = try decoder.decode(AppConfig.self, from: Data(json.utf8))

    XCTAssertEqual(issues.issues.count, 2)
    XCTAssertTrue(issues.issues.contains { $0.contains("showHUD") })
    XCTAssertTrue(issues.issues.contains { $0.contains("weird") })
    // Principle V: issue text names keys and ids, never the offending values
    // (config.json holds user-authored prompts).
    XCTAssertFalse(issues.issues.contains { $0.contains("yes") })
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
