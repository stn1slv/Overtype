import XCTest

@testable import Overtype

/// specs/010-model-aware-parameters (FR-020 to FR-022): the Actions editor's
/// validation of the two optional generation settings. Pure and static, like
/// `SettingsViewModel.shouldAdoptReloadedConfig`, because `saveAction` itself
/// writes through the shared config store.
final class ActionParameterValidationTests: XCTestCase {

  private func normalize(_ temperature: Double?, _ effort: String?) throws -> (Double?, String?) {
    try SettingsViewModel.normalizedGenerationOverrides(
      temperature: temperature, reasoningEffort: effort)
  }

  func testAutomaticTemperaturePasses() throws {
    XCTAssertNil(try normalize(nil, nil).0)
  }

  func testTemperatureBoundsAreInclusive() throws {
    XCTAssertEqual(try normalize(0.0, nil).0, 0.0)
    XCTAssertEqual(try normalize(2.0, nil).0, 2.0)
  }

  func testOutOfRangeTemperatureThrowsTheExistingError() {
    for value in [-0.1, 2.1] {
      XCTAssertThrowsError(try normalize(value, nil)) { error in
        XCTAssertEqual((error as NSError).code, 13)
      }
    }
  }

  func testReasoningEffortIsTrimmedAndBlankMeansAutomatic() throws {
    XCTAssertEqual(try normalize(nil, "  low ").1, "low")
    XCTAssertNil(try normalize(nil, "   ").1)
    XCTAssertNil(try normalize(nil, nil).1)
  }

  func testHandEditedEffortOutsideTheListIsKept() throws {
    XCTAssertEqual(try normalize(nil, "ultra").1, "ultra")
  }
}
