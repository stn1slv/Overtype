import XCTest

@testable import Overtype

/// C7: the reload decision must compare the draft against the LAST LOADED
/// snapshot, not against the store. Comparing against the store conflated
/// "user has unsaved edits" with "someone else changed the config", which made
/// the old reload a permanent no-op and let GUI saves overwrite hand edits.
final class SettingsReloadTests: XCTestCase {

  private func makeConfig(multiplier: Double = 1.0, actionTitle: String = "Fix") -> AppConfig {
    AppConfig(
      global: GeneralConfig(typingSpeedMultiplier: multiplier),
      providers: [ProviderConfig(id: "p1", kind: .openAICompatible, defaultModel: "m")],
      actions: [
        ActionConfig(
          id: "a1", title: actionTitle, enabled: true, providerID: "p1",
          systemPrompt: "s", userPromptTemplate: "{{text}}")
      ])
  }

  func testCleanDraftAdoptsReloadedConfig() {
    let snapshot = makeConfig()
    let overrides = [AppOverrideDraft(bundleID: "com.apple.Notes", chunkSize: 5, delay: nil)]
    XCTAssertTrue(
      SettingsViewModel.shouldAdoptReloadedConfig(
        draft: snapshot, lastLoaded: snapshot,
        draftOverrides: overrides, lastLoadedOverrides: overrides))
  }

  func testEditedGlobalKeepsDraft() {
    let snapshot = makeConfig(multiplier: 1.0)
    let draft = makeConfig(multiplier: 2.0)
    XCTAssertFalse(
      SettingsViewModel.shouldAdoptReloadedConfig(
        draft: draft, lastLoaded: snapshot, draftOverrides: [], lastLoadedOverrides: []))
  }

  func testEditedActionKeepsDraft() {
    let snapshot = makeConfig(actionTitle: "Fix")
    let draft = makeConfig(actionTitle: "Fix grammar")
    XCTAssertFalse(
      SettingsViewModel.shouldAdoptReloadedConfig(
        draft: draft, lastLoaded: snapshot, draftOverrides: [], lastLoadedOverrides: []))
  }

  func testInProgressOverrideRowKeepsDraft() {
    // A newly added, still-empty override row is an unsaved edit even though
    // the dictionary form of the config is unchanged.
    let snapshot = makeConfig()
    let draftRows = [AppOverrideDraft(bundleID: "", chunkSize: nil, delay: nil)]
    XCTAssertFalse(
      SettingsViewModel.shouldAdoptReloadedConfig(
        draft: snapshot, lastLoaded: snapshot,
        draftOverrides: draftRows, lastLoadedOverrides: []))
  }

  func testExternalChangeAloneDoesNotBlockAdoption() {
    // The store may differ arbitrarily from the snapshot (that is the external
    // edit being imported); only draft-vs-snapshot divergence blocks adoption.
    let snapshot = makeConfig()
    XCTAssertTrue(
      SettingsViewModel.shouldAdoptReloadedConfig(
        draft: snapshot, lastLoaded: snapshot, draftOverrides: [], lastLoadedOverrides: []))
  }
}
