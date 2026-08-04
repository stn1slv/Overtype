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

  func testDisplayStringNeverContainsEmptyParentheses() {
    for version in [nil, "", "   ", "1.2.1"] {
      for build in [nil, "", "   ", "20"] {
        XCTAssertFalse(display(version, build).contains("()"))
      }
    }
  }
}
