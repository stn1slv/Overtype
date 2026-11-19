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

  // MARK: - Form input (specs/011 FR-010, FR-012)

  func testAppleIgnoresAnInvalidHiddenURLAndATypedKey() throws {
    let input = try SettingsViewModel.validatedEndpointInput(
      kind: .apple, baseURLString: "not a url", apiKey: "sk-123", model: "system")
    XCTAssertNil(input.url)
    XCTAssertEqual(input.apiKey, "")
  }

  func testAppleRejectsAnyOtherModel() {
    XCTAssertThrowsError(
      try SettingsViewModel.validatedEndpointInput(
        kind: .apple, baseURLString: "", apiKey: "", model: "gpt-6-luna")
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("system"))
    }
  }

  func testOtherKindsStillValidateTheURL() throws {
    XCTAssertThrowsError(
      try SettingsViewModel.validatedEndpointInput(
        kind: .ollama, baseURLString: "not a url", apiKey: "", model: "llama3.2"))
    let input = try SettingsViewModel.validatedEndpointInput(
      kind: .openAICompatible, baseURLString: " https://api.openai.com/v1 ", apiKey: "sk",
      model: "gpt-6-luna")
    XCTAssertEqual(input.url?.absoluteString, "https://api.openai.com/v1")
    XCTAssertEqual(input.apiKey, "sk")
  }

  // MARK: - Stale Keychain reference on edit

  private func provider(_ id: String, _ kind: ProviderKind, key: String?) -> ProviderConfig {
    ProviderConfig(id: id, kind: kind, defaultModel: "m", keychainKey: key)
  }

  func testSwitchingToAppleDropsAndDeletesTheKey() {
    let result = SettingsViewModel.staleKeyHandling(
      original: provider("openai", .openAICompatible, key: "overtype-openai-key"),
      newKind: .apple, apiKey: "", otherProviders: [])
    XCTAssertTrue(result.dropReference)
    XCTAssertEqual(result.deleteItem, "overtype-openai-key")
  }

  func testSavingAppleWithoutKindChangeDropsTheReferenceOnly() {
    let result = SettingsViewModel.staleKeyHandling(
      original: provider("apple", .apple, key: "copied-key"), newKind: .apple, apiKey: "",
      otherProviders: [])
    XCTAssertTrue(result.dropReference)
    XCTAssertNil(result.deleteItem)
  }

  func testASharedKeyIsNeverDeleted() {
    let result = SettingsViewModel.staleKeyHandling(
      original: provider("openai", .openAICompatible, key: "shared"), newKind: .apple,
      apiKey: "", otherProviders: [provider("other", .openAICompatible, key: "shared")])
    XCTAssertTrue(result.dropReference)
    XCTAssertNil(result.deleteItem)
  }

  func testSameKindEditKeepsTheKey() {
    let result = SettingsViewModel.staleKeyHandling(
      original: provider("openai", .openAICompatible, key: "k"), newKind: .openAICompatible,
      apiKey: "", otherProviders: [])
    XCTAssertFalse(result.dropReference)
    XCTAssertNil(result.deleteItem)
  }
}
