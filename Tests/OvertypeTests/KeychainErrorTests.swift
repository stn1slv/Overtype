import Security
import XCTest

@testable import Overtype

/// C4: Settings used to render a Keychain failure as the opaque
/// "KeychainError error 0."; the OSStatus was carried but never shown or
/// logged, leaving credential problems undiagnosable.
final class KeychainErrorTests: XCTestCase {

  func testUnhandledErrorNamesTheStatusCode() {
    let error = KeychainError.unhandledError(status: errSecInteractionNotAllowed)
    XCTAssertTrue(
      error.localizedDescription.contains("\(errSecInteractionNotAllowed)"),
      "expected the numeric OSStatus in: \(error.localizedDescription)")
  }

  func testUnhandledErrorIncludesSystemMessageText() {
    // SecCopyErrorMessageString provides human-readable text for security
    // framework statuses; the rendered message must carry more than the number.
    let error = KeychainError.unhandledError(status: errSecAuthFailed)
    let message = error.localizedDescription
    XCTAssertTrue(
      message.rangeOfCharacter(from: .letters) != nil && message.count > 12,
      "expected readable text in: \(message)")
  }

  func testItemNotFoundHasReadableMessage() {
    let message = KeychainError.itemNotFound.localizedDescription
    XCTAssertTrue(
      message.localizedCaseInsensitiveContains("keychain"),
      "expected a keychain-specific message, got: \(message)")
  }
}
