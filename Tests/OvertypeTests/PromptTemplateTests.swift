import XCTest

@testable import Overtype

final class PromptTemplateTests: XCTestCase {

  func testPromptSubstitution() {
    let template = "Correct this: {{text}}"
    let input = "I is good."

    let result = template.replacingOccurrences(of: "{{text}}", with: input)
    XCTAssertEqual(result, "Correct this: I is good.")
  }
}
