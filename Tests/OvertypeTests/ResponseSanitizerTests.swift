import XCTest

@testable import Overtype

final class ResponseSanitizerTests: XCTestCase {

  let sanitizer = ResponseSanitizer()

  func testStripsConversationalPrefixes() {
    let original = "Hello"
    let rawResponse = "Here is the corrected text:\nHello"
    let result = sanitizer.sanitize(response: rawResponse, originalText: original)
    XCTAssertEqual(result, "Hello")
  }

  func testStripsQuotesIfOriginalDidNotHaveThem() {
    let original = "Hello world"
    let rawResponse = "\"Hello world.\""
    let result = sanitizer.sanitize(response: rawResponse, originalText: original)
    XCTAssertEqual(result, "Hello world.")
  }

  func testKeepsQuotesIfOriginalHadThem() {
    let original = "\"Hello world\""
    let rawResponse = "\"Hello world.\""
    let result = sanitizer.sanitize(response: rawResponse, originalText: original)
    XCTAssertEqual(result, "\"Hello world.\"")
  }

  func testStripsMarkdownBlocks() {
    let original = "let x = 1"
    let rawResponse = "```swift\nlet x = 1\n```"
    let result = sanitizer.sanitize(response: rawResponse, originalText: original)
    XCTAssertEqual(result, "let x = 1")
  }

  func testLeavesNormalTextAlone() {
    let original = "This is a test"
    let rawResponse = "This is a test."
    let result = sanitizer.sanitize(response: rawResponse, originalText: original)
    XCTAssertEqual(result, "This is a test.")
  }

  func testKeepsNewlinesByDefault() {
    let original = "Line one\nLine two"
    let rawResponse = "Line one\nLine two"
    let result = sanitizer.sanitize(response: rawResponse, originalText: original)
    XCTAssertEqual(result, "Line one\nLine two")
  }

  func testCollapsesNewlinesWhenNotAllowed() {
    let original = "Line one Line two"
    let rawResponse = "Line one\nLine two"
    let result = sanitizer.sanitize(
      response: rawResponse, originalText: original, allowNewlines: false)
    XCTAssertEqual(result, "Line one Line two")
  }

  func testCollapsesBlankLinesAndTrimsWhenNotAllowed() {
    let original = "A B C"
    let rawResponse = "A\n\n  B  \nC"
    let result = sanitizer.sanitize(
      response: rawResponse, originalText: original, allowNewlines: false)
    XCTAssertEqual(result, "A B C")
  }
}
