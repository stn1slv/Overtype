import XCTest

@testable import Overtype

/// Covers `ActionEngine.retryDelayNanoseconds(forSeconds:)`. The clamp exists
/// because `config.json` is a hand-editable surface and both extremes trap at
/// runtime, so every case here is a crash the app would otherwise take.
final class RetryDelayClampTests: XCTestCase {

  private let nanosecondsPerSecond: UInt64 = 1_000_000_000

  // MARK: - Ordinary values pass through

  func testDefaultDelayConvertsExactly() {
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: 0.5), 500_000_000)
  }

  func testWholeSecondConvertsExactly() {
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: 2), 2 * nanosecondsPerSecond)
  }

  func testSliderMaximumConvertsExactly() {
    // 5s is the ceiling of the Providers tab slider.
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: 5), 5 * nanosecondsPerSecond)
  }

  // MARK: - Zero and below mean "no sleep"

  func testZeroMeansRetryImmediately() {
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: 0), 0)
  }

  func testNegativeIsTreatedAsZero() {
    // UInt64(negative) would trap.
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: -1), 0)
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: -1e9), 0)
  }

  // MARK: - Non-finite values

  func testNaNIsTreatedAsZero() {
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: .nan), 0)
  }

  func testInfinityIsTreatedAsZero() {
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: .infinity), 0)
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: -.infinity), 0)
  }

  // MARK: - Large values are clamped, not overflowed

  func testHugeValueIsClampedToMaximum() {
    // Verified to trap before the clamp: "Double value cannot be converted to
    // UInt64 because the result would be greater than UInt64.max".
    let expected = UInt64(ActionEngine.maxRetryDelaySeconds) * nanosecondsPerSecond
    XCTAssertEqual(ActionEngine.retryDelayNanoseconds(forSeconds: 1e11), expected)
  }

  func testGreatestFiniteMagnitudeIsClampedToMaximum() {
    let expected = UInt64(ActionEngine.maxRetryDelaySeconds) * nanosecondsPerSecond
    XCTAssertEqual(
      ActionEngine.retryDelayNanoseconds(forSeconds: .greatestFiniteMagnitude), expected)
  }

  func testValueJustAboveMaximumIsClamped() {
    let expected = UInt64(ActionEngine.maxRetryDelaySeconds) * nanosecondsPerSecond
    XCTAssertEqual(
      ActionEngine.retryDelayNanoseconds(forSeconds: ActionEngine.maxRetryDelaySeconds + 1),
      expected)
  }

  func testResultNeverExceedsMaximum() {
    let ceiling = UInt64(ActionEngine.maxRetryDelaySeconds) * nanosecondsPerSecond
    for seconds in [-5.0, 0.0, 0.5, 5.0, 59.9, 60.0, 61.0, 1e6, 1e11, .greatestFiniteMagnitude] {
      XCTAssertLessThanOrEqual(
        ActionEngine.retryDelayNanoseconds(forSeconds: seconds), ceiling,
        "delay of \(seconds)s exceeded the clamp")
    }
  }
}
