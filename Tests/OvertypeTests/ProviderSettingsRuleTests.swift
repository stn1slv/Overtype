import XCTest

@testable import Overtype

/// specs/011 FR-012: a provider kind that runs on this Mac stores no endpoint
/// and no Keychain reference.
final class ProviderSettingsRuleTests: XCTestCase {

  private let url = URL(string: "http://localhost:11434")

  func testAppleKeepsNeitherEndpointNorKey() {
    let stored = SettingsViewModel.storedEndpointAndKey(
      kind: .apple, url: url, keychainKey: "overtype-apple-key")
    XCTAssertNil(stored.url)
    XCTAssertNil(stored.keychainKey)
  }

  func testOtherKindsKeepBoth() {
    for kind in [ProviderKind.openAICompatible, .ollama, .gemini, .anthropic] {
      let stored = SettingsViewModel.storedEndpointAndKey(
        kind: kind, url: url, keychainKey: "overtype-x-key")
      XCTAssertEqual(stored.url, url, "\(kind)")
      XCTAssertEqual(stored.keychainKey, "overtype-x-key", "\(kind)")
    }
  }

  func testAppleRecordDecodesWithoutIssues() throws {
    let json = #"{"id":"apple","kind":"apple","defaultModel":"system","timeoutSeconds":60}"#
    let issues = ConfigDecodingIssues()
    let decoder = JSONDecoder()
    ConfigDecodingIssues.attach(issues, to: decoder)
    let provider = try decoder.decode(ProviderConfig.self, from: Data(json.utf8))
    XCTAssertEqual(provider.kind, .apple)
    XCTAssertNil(provider.baseURL)
    XCTAssertNil(provider.keychainKey)
    XCTAssertEqual(issues.issues, [])
  }
}
