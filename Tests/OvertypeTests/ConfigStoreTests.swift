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
