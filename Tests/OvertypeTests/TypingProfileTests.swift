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
