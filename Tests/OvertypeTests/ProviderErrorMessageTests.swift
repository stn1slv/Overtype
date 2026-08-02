import XCTest
@testable import Overtype

final class ProviderErrorMessageTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testExtractsOpenAIStyleErrorMessage() {
        let body = #"{"error": {"message": "Invalid API key", "type": "auth"}}"#
        let result = OpenAICompatibleProvider.extractErrorMessage(from: data(body))
        XCTAssertEqual(result, "Invalid API key")
    }

    func testFallsBackToRawBodyWhenNotOpenAIShaped() {
        let body = "Service Unavailable"
        let result = OpenAICompatibleProvider.extractErrorMessage(from: data(body))
        XCTAssertEqual(result, "Service Unavailable")
    }

    func testEmptyBodyReturnsPlaceholder() {
        let result = OpenAICompatibleProvider.extractErrorMessage(from: Data())
        XCTAssertEqual(result, "Server returned an error with no readable body.")
    }

    func testLongRawBodyIsTruncated() {
        let body = String(repeating: "x", count: 500)
        let result = OpenAICompatibleProvider.extractErrorMessage(from: data(body))
        XCTAssertTrue(result.hasSuffix("…"))
        // 200 characters plus the ellipsis.
        XCTAssertEqual(result.count, 201)
    }
}
