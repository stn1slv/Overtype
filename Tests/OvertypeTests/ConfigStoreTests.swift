import XCTest

@testable import Overtype

final class ConfigStoreTests: XCTestCase {

  func testDefaultConfigIsValidJSON() {
    let json = DefaultConfig.defaultConfigJSON
    let data = json.data(using: .utf8)!

    let decoder = JSONDecoder()
    XCTAssertNoThrow(try decoder.decode(AppConfig.self, from: data))
  }

  func testDefaultConfigContainsGrammarAction() {
    let config = DefaultConfig.defaultConfig
    XCTAssertNotNil(config)
    XCTAssertEqual(config?.actions.first?.id, "fix-grammar")
    XCTAssertEqual(config?.actions.first?.providerID, "openai")
  }

  func testExistingConfigKeepsItsModelAndTemperature() throws {
    // specs/010 FR-019: an upgrade never swaps a configured model for the new
    // seeded default. ConfigStore seeds only when no file exists and otherwise
    // decodes the file as below, so the stored values must survive the decode.
    let json = #"""
      {
        "providers": [
          {"id": "openai", "kind": "openai", "baseURL": "https://api.openai.com/v1",
           "defaultModel": "gpt-5.4-nano", "keychainKey": "k"}
        ],
        "actions": [
          {"id": "fix-grammar", "title": "Fix grammar", "providerID": "openai",
           "systemPrompt": "s", "userPromptTemplate": "{{text}}", "temperature": 0}
        ]
      }
      """#
    let issues = ConfigDecodingIssues()
    let decoder = JSONDecoder()
    ConfigDecodingIssues.attach(issues, to: decoder)
    let config = try decoder.decode(AppConfig.self, from: Data(json.utf8))
    XCTAssertEqual(config.providers.first?.defaultModel, "gpt-5.4-nano")
    XCTAssertEqual(config.actions.first?.temperature, 0)
    XCTAssertTrue(issues.issues.isEmpty)
  }

  func testDefaultConfigHasVerifiedOutlookTypingOverride() {
    let override = DefaultConfig.defaultConfig?.global.appTypingOverrides?["com.microsoft.Outlook"]
    XCTAssertEqual(override?.typingChunkSize, 1)
    XCTAssertEqual(override?.typingDelayMicroseconds, 10000)
  }

  func testInvalidBackupFileNameFormat() {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 3
    components.hour = 14
    components.minute = 5
    components.second = 9
    components.timeZone = TimeZone.current
    let date = Calendar(identifier: .gregorian).date(from: components)!

    XCTAssertEqual(
      ConfigStore.invalidBackupFileName(for: date), "config.json.invalid-20260803-140509")
  }
}
