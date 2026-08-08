import XCTest

@testable import Overtype

final class TypingProfileTests: XCTestCase {

  private let outlook = "com.microsoft.Outlook"
  private let notes = "com.apple.Notes"

  func testUsesGlobalWhenNoOverrides() {
    let settings = GeneralConfig(
      typingChunkSize: 20, typingDelayMicroseconds: 2000, appTypingOverrides: nil)
    let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
    XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
  }

  func testFallsBackToBuiltInDefaultsWhenGlobalNil() {
    let settings = GeneralConfig(
      typingChunkSize: nil, typingDelayMicroseconds: nil, appTypingOverrides: nil)
    let profile = TextWriter.typingProfile(bundleID: nil, settings: settings)
    XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
  }

  func testAppliesMatchingOverride() {
    let settings = GeneralConfig(
      typingChunkSize: 20, typingDelayMicroseconds: 2000,
      appTypingOverrides: [
        outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: 10000)
      ]
    )
    let profile = TextWriter.typingProfile(bundleID: outlook, settings: settings)
    XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 1, delayMicroseconds: 10000))
  }

  func testNonMatchingBundleUsesGlobal() {
    let settings = GeneralConfig(
      typingChunkSize: 20, typingDelayMicroseconds: 2000,
      appTypingOverrides: [
        outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: 10000)
      ]
    )
    let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
    XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
  }

  func testNilBundleUsesGlobalEvenWithOverrides() {
    let settings = GeneralConfig(
      appTypingOverrides: [
        outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: 10000)
      ]
    )
    let profile = TextWriter.typingProfile(bundleID: nil, settings: settings)
    XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
  }

  func testPartialOverrideFillsMissingFieldFromGlobal() {
    let settings = GeneralConfig(
      typingChunkSize: 30, typingDelayMicroseconds: 5000,
      appTypingOverrides: [
        outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: nil)
      ]
    )
    let profile = TextWriter.typingProfile(bundleID: outlook, settings: settings)
    // chunkSize comes from the override; the missing delay falls back to global.
    XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 1, delayMicroseconds: 5000))
  }

  func testPartialOverrideWithNilGlobalFallsBackToBuiltInDefaults() {
    let settings = GeneralConfig(
      typingChunkSize: nil, typingDelayMicroseconds: nil,
      appTypingOverrides: [
        outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: nil)
      ]
    )
    let profile = TextWriter.typingProfile(bundleID: outlook, settings: settings)
    // chunkSize from the override; delay falls through nil global to the built-in 2000.
    XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 1, delayMicroseconds: 2000))
  }

  // MARK: - Cadence normalization (C2): a hand-edited chunk size outside the
  // safe range must never reach the event loop. Non-positive behaves like the
  // Settings field's 0 sentinel ("unset"), oversized clamps to the verified
  // per-event cap. One unbounded synthetic event silently truncates, which is
  // the data-loss path this guards.

  func testChunkSizeZeroFallsBackToDefault() {
    // Decoded 0 bypasses the `?? 20` fallback (0 is non-nil), so the profile
    // itself must normalize it.
    let settings = GeneralConfig(typingChunkSize: 0, typingDelayMicroseconds: 2000)
    let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
    XCTAssertEqual(profile.chunkSize, 20)
  }

  func testNegativeChunkSizeFallsBackToDefault() {
    let settings = GeneralConfig(typingChunkSize: -5, typingDelayMicroseconds: 2000)
    let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
    XCTAssertEqual(profile.chunkSize, 20)
  }

  func testOversizedChunkSizeClampsToCap() {
    let settings = GeneralConfig(typingChunkSize: 500, typingDelayMicroseconds: 2000)
    let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
    XCTAssertEqual(profile.chunkSize, TextWriter.maxChunkSizeUTF16)
  }

  func testChunkSizeBoundaryValuesPassThrough() {
    let one = GeneralConfig(typingChunkSize: 1, typingDelayMicroseconds: 2000)
    XCTAssertEqual(TextWriter.typingProfile(bundleID: notes, settings: one).chunkSize, 1)
    let twenty = GeneralConfig(typingChunkSize: 20, typingDelayMicroseconds: 2000)
    XCTAssertEqual(TextWriter.typingProfile(bundleID: notes, settings: twenty).chunkSize, 20)
  }

  func testOverrideChunkZeroFallsBackToGlobal() {
    let settings = GeneralConfig(
      typingChunkSize: 10, typingDelayMicroseconds: 2000,
      appTypingOverrides: [outlook: AppTypingOverride(typingChunkSize: 0)])
    let profile = TextWriter.typingProfile(bundleID: outlook, settings: settings)
    XCTAssertEqual(profile.chunkSize, 10)
  }

  func testOverrideOversizedChunkClampsToCap() {
    let settings = GeneralConfig(
      typingChunkSize: 10, typingDelayMicroseconds: 2000,
      appTypingOverrides: [outlook: AppTypingOverride(typingChunkSize: 100)])
    let profile = TextWriter.typingProfile(bundleID: outlook, settings: settings)
    XCTAssertEqual(profile.chunkSize, TextWriter.maxChunkSizeUTF16)
  }

  func testNegativeDelayFallsBackToDefault() {
    // Explicit 0 stays valid ("no delay"); only negative is unusable.
    let settings = GeneralConfig(typingChunkSize: 20, typingDelayMicroseconds: -100)
    let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
    XCTAssertEqual(profile.delayMicroseconds, 2000)
  }

  func testZeroDelayStaysZero() {
    let settings = GeneralConfig(typingChunkSize: 20, typingDelayMicroseconds: 0)
    let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
    XCTAssertEqual(profile.delayMicroseconds, 0)
  }

  func testChunkRangesWithNonPositiveChunkSizeStaysBounded() {
    // Defense in depth behind the profile clamp: even called directly with a
    // bad size, chunkRanges must never emit one unbounded range.
    let text = Array(String(repeating: "a", count: 50).utf16)
    let ranges = TextWriter.chunkRanges(for: text, chunkSize: 0)
    XCTAssertTrue(ranges.allSatisfy { $0.count <= TextWriter.maxChunkSizeUTF16 })
    XCTAssertEqual(ranges.reduce(0) { $0 + $1.count }, 50)
  }

  func testEffectiveDelayScalesWithMultiplier() {
    XCTAssertEqual(TextWriter.effectiveDelayMicroseconds(base: 2000, speedMultiplier: 1.0), 2000)
    XCTAssertEqual(TextWriter.effectiveDelayMicroseconds(base: 2000, speedMultiplier: 2.0), 1000)
    XCTAssertEqual(TextWriter.effectiveDelayMicroseconds(base: 2000, speedMultiplier: 0.5), 4000)
  }

  func testEffectiveDelayGuardsNonPositiveMultiplier() {
    // A zero or negative multiplier must not trap (division by zero -> Int(inf)).
    // It is treated as the neutral 1.0, returning the base delay unchanged.
    XCTAssertEqual(TextWriter.effectiveDelayMicroseconds(base: 2000, speedMultiplier: 0.0), 2000)
    XCTAssertEqual(TextWriter.effectiveDelayMicroseconds(base: 2000, speedMultiplier: -3.0), 2000)
  }

  func testEffectiveDelayIsCappedAtOneSecond() {
    // A small positive multiplier scales the delay above the 1-second cap.
    XCTAssertEqual(
      TextWriter.effectiveDelayMicroseconds(base: 2000, speedMultiplier: 0.001), 1_000_000)
  }

  func testEffectiveDelayDoesNotTrapOnTinyPositiveMultiplier() {
    // Without clamping, base / 1e-300 exceeds Int.max and Int() traps. It must
    // instead clamp to the 1-second cap.
    XCTAssertEqual(
      TextWriter.effectiveDelayMicroseconds(base: 2000, speedMultiplier: 1e-300), 1_000_000)
  }

  func testEffectiveDelayFloorsNegativeBaseAtZero() {
    XCTAssertEqual(TextWriter.effectiveDelayMicroseconds(base: -5000, speedMultiplier: 1.0), 0)
  }
}
