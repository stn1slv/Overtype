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
