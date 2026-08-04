import XCTest

@testable import Overtype

final class AppVersionTests: XCTestCase {

  private func display(_ shortVersion: String?, _ build: String?) -> String {
    AppVersion(shortVersion: shortVersion, build: build).displayString
  }

  func testBothValuesPresent() {
    XCTAssertEqual(display("1.2.1", "20"), "1.2.1 (20)")
  }

  func testBuildAbsentShowsVersionAlone() {
    XCTAssertEqual(display("1.2.1", nil), "1.2.1")
  }

  func testVersionAbsentShowsUnknown() {
    XCTAssertEqual(display(nil, "20"), "Unknown")
  }

  func testBothAbsentShowsUnknown() {
    XCTAssertEqual(display(nil, nil), "Unknown")
  }

  func testWhitespaceOnlyVersionTreatedAsAbsent() {
    XCTAssertEqual(display("   ", "20"), "Unknown")
  }

  func testWhitespaceOnlyBuildTreatedAsAbsent() {
    XCTAssertEqual(display("1.2.1", "  "), "1.2.1")
  }

  func testEmptyStringsTreatedAsAbsent() {
    XCTAssertEqual(display("", ""), "Unknown")
  }

  func testSurroundingWhitespaceIsTrimmed() {
    XCTAssertEqual(display("  1.2.1\n", " 20 "), "1.2.1 (20)")
  }

  func testPreReleaseVersionPassedThroughUnchanged() {
    XCTAssertEqual(display("1.3.0-beta.1", "21"), "1.3.0-beta.1 (21)")
  }

  func testUnstampedLocalBuildSentinelIsShownVerbatim() {
    // scripts/build-app.sh leaves CFBundleVersion at the checked-in 0 when the
    // build was not stamped; that is displayed as-is, not special-cased.
    XCTAssertEqual(display("1.2.1", "0"), "1.2.1 (0)")
  }

  func testDisplayStringIsNeverEmpty() {
    for version in [nil, "", "   ", "1.2.1"] {
      for build in [nil, "", "   ", "20"] {
        XCTAssertFalse(display(version, build).isEmpty)
      }
    }
  }

  // MARK: - Info dictionary extraction

  func testReadsBothKeysFromInfoDictionary() {
    let version = AppVersion(infoDictionary: [
      "CFBundleShortVersionString": "1.2.1",
      "CFBundleVersion": "20",
    ])
    XCTAssertEqual(version, AppVersion(shortVersion: "1.2.1", build: "20"))
    XCTAssertEqual(version.displayString, "1.2.1 (20)")
  }

  func testNilInfoDictionaryYieldsUnknown() {
    XCTAssertEqual(AppVersion(infoDictionary: nil).displayString, "Unknown")
  }

  func testEmptyInfoDictionaryYieldsUnknown() {
    XCTAssertEqual(AppVersion(infoDictionary: [:]).displayString, "Unknown")
  }

  func testNonStringValuesAreTreatedAsAbsent() {
    // A hand-edited plist could declare these as <integer>; the cast fails and
    // the value must be treated as missing rather than crashing or printing a
    // description like "Optional(20)".
    let version = AppVersion(infoDictionary: [
      "CFBundleShortVersionString": 121,
      "CFBundleVersion": 20,
    ])
    XCTAssertNil(version.shortVersion)
    XCTAssertNil(version.build)
    XCTAssertEqual(version.displayString, "Unknown")
  }

  func testNonStringBuildStillShowsTheVersion() {
    let version = AppVersion(infoDictionary: [
      "CFBundleShortVersionString": "1.2.1",
      "CFBundleVersion": 20,
    ])
    XCTAssertEqual(version.displayString, "1.2.1")
  }

  func testDisplayStringNeverContainsEmptyParentheses() {
    for version in [nil, "", "   ", "1.2.1"] {
      for build in [nil, "", "   ", "20"] {
        XCTAssertFalse(display(version, build).contains("()"))
      }
    }
  }
}
