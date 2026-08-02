import XCTest
@testable import Overtype

final class TypingProfileTests: XCTestCase {

    private let outlook = "com.microsoft.Outlook"
    private let notes = "com.apple.Notes"

    func testUsesGlobalWhenNoOverrides() {
        let settings = GeneralConfig(typingChunkSize: 20, typingDelayMicroseconds: 2000, appTypingOverrides: nil)
        let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
        XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
    }

    func testFallsBackToBuiltInDefaultsWhenGlobalNil() {
        let settings = GeneralConfig(typingChunkSize: nil, typingDelayMicroseconds: nil, appTypingOverrides: nil)
        let profile = TextWriter.typingProfile(bundleID: nil, settings: settings)
        XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
    }

    func testAppliesMatchingOverride() {
        let settings = GeneralConfig(
            typingChunkSize: 20, typingDelayMicroseconds: 2000,
            appTypingOverrides: [outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: 10000)]
        )
        let profile = TextWriter.typingProfile(bundleID: outlook, settings: settings)
        XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 1, delayMicroseconds: 10000))
    }

    func testNonMatchingBundleUsesGlobal() {
        let settings = GeneralConfig(
            typingChunkSize: 20, typingDelayMicroseconds: 2000,
            appTypingOverrides: [outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: 10000)]
        )
        let profile = TextWriter.typingProfile(bundleID: notes, settings: settings)
        XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
    }

    func testNilBundleUsesGlobalEvenWithOverrides() {
        let settings = GeneralConfig(
            appTypingOverrides: [outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: 10000)]
        )
        let profile = TextWriter.typingProfile(bundleID: nil, settings: settings)
        XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 20, delayMicroseconds: 2000))
    }

    func testPartialOverrideFillsMissingFieldFromGlobal() {
        let settings = GeneralConfig(
            typingChunkSize: 30, typingDelayMicroseconds: 5000,
            appTypingOverrides: [outlook: AppTypingOverride(typingChunkSize: 1, typingDelayMicroseconds: nil)]
        )
        let profile = TextWriter.typingProfile(bundleID: outlook, settings: settings)
        // chunkSize comes from the override; the missing delay falls back to global.
        XCTAssertEqual(profile, TextWriter.TypingProfile(chunkSize: 1, delayMicroseconds: 5000))
    }
}
