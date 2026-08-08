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
    // The boundary shrinks so the pair moves whole into the next chunk; no
    // chunk exceeds chunkSize (C2 review fix: extending past the size could
    // exceed the per-event cap at the maximum chunk size).
    XCTAssertEqual(ranges, [0..<1, 1..<3, 3..<4])

    // Every chunk must be independently decodable (no lone surrogate), and the
    // concatenation must reproduce the original string.
    let reassembled = ranges.map { String(utf16CodeUnits: Array(utf16[$0]), count: $0.count) }
      .joined()
    XCTAssertEqual(reassembled, text)
  }

  func testSurrogateAtCapBoundaryNeverExceedsCap() {
    // 19 ASCII units followed by an emoji put the pair exactly astride the
    // 20-unit boundary. The old extend-by-one emitted a 21-unit chunk here,
    // which the OS event cap would silently truncate into a lone high
    // surrogate after the selection was already deleted (C2 review fix).
    let text = String(repeating: "a", count: 19) + "😀" + "tail"
    let utf16 = units(text)
    let ranges = TextWriter.chunkRanges(for: utf16, chunkSize: TextWriter.maxChunkSizeUTF16)

    XCTAssertTrue(
      ranges.allSatisfy { $0.count <= TextWriter.maxChunkSizeUTF16 },
      "a chunk exceeded the per-event cap: \(ranges)")
    let reassembled = ranges.map { String(utf16CodeUnits: Array(utf16[$0]), count: $0.count) }
      .joined()
    XCTAssertEqual(reassembled, text)
    for range in ranges {
      XCTAssertFalse((0xD800...0xDBFF).contains(utf16[range.upperBound - 1]))
      XCTAssertFalse((0xDC00...0xDFFF).contains(utf16[range.lowerBound]))
    }
  }

  func testChunkSizeOneCarriesPairsAsTwoUnitChunks() {
    // chunkSize 1 is the shipped Outlook override. Shrinking would empty the
    // range, so a pair travels as one 2-unit chunk: the invariant is
    // count <= max(chunkSize, 2), still far below the event cap.
    let text = "😀a😀"
    let utf16 = units(text)
    let ranges = TextWriter.chunkRanges(for: utf16, chunkSize: 1)
    XCTAssertEqual(ranges, [0..<2, 2..<3, 3..<5])
    XCTAssertTrue(ranges.allSatisfy { $0.count <= 2 })
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
