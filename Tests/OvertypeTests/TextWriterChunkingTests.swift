import XCTest

@testable import Overtype

final class TextWriterChunkingTests: XCTestCase {

  private func units(_ string: String) -> [UInt16] { Array(string.utf16) }

  func testEmptyInputProducesNoRanges() {
    XCTAssertTrue(TextWriter.chunkRanges(for: [], chunkSize: 20).isEmpty)
  }

  func testEvenChunking() {
    let ranges = TextWriter.chunkRanges(for: units("abcdef"), chunkSize: 2)
    XCTAssertEqual(ranges, [0..<2, 2..<4, 4..<6])
  }

  func testFinalChunkShorterThanChunkSize() {
    let ranges = TextWriter.chunkRanges(for: units("abcde"), chunkSize: 2)
    XCTAssertEqual(ranges, [0..<2, 2..<4, 4..<5])
  }

  func testNonPositiveChunkSizeReturnsSingleRange() {
    let ranges = TextWriter.chunkRanges(for: units("abc"), chunkSize: 0)
    XCTAssertEqual(ranges, [0..<3])
  }

  func testSurrogatePairIsNotSplitAcrossChunks() {
    // "a😀b": UTF-16 is [a, highSurrogate, lowSurrogate, b] (4 units).
    // A naive size-2 split would break the emoji at the 0..<2 boundary.
    let text = "a😀b"
    let utf16 = units(text)
    XCTAssertEqual(utf16.count, 4)

    let ranges = TextWriter.chunkRanges(for: utf16, chunkSize: 2)
    // The high surrogate at index 1 pulls its low surrogate into the first chunk.
    XCTAssertEqual(ranges, [0..<3, 3..<4])

    // Every chunk must be independently decodable (no lone surrogate), and the
    // concatenation must reproduce the original string.
    let reassembled = ranges.map { String(utf16CodeUnits: Array(utf16[$0]), count: $0.count) }
      .joined()
    XCTAssertEqual(reassembled, text)
  }

  func testConsecutiveEmojiRemainValid() {
    let text = "😀😀😀"
    let utf16 = units(text)
    let ranges = TextWriter.chunkRanges(for: utf16, chunkSize: 3)
    let reassembled = ranges.map { String(utf16CodeUnits: Array(utf16[$0]), count: $0.count) }
      .joined()
    XCTAssertEqual(reassembled, text)
    // No chunk may start or end on a lone surrogate.
    for range in ranges {
      let first = utf16[range.lowerBound]
      let last = utf16[range.upperBound - 1]
      XCTAssertFalse((0xDC00...0xDFFF).contains(first), "chunk starts on a low surrogate")
      XCTAssertFalse((0xD800...0xDBFF).contains(last), "chunk ends on a high surrogate")
    }
  }
}
