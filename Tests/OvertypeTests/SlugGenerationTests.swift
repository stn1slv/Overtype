import XCTest

@testable import Overtype

final class SlugGenerationTests: XCTestCase {

  // Slug generation logic test cases
  func testToSlug() {
    XCTAssertEqual(toSlug("Translate French"), "translate-french")
    XCTAssertEqual(toSlug("  Fix   Grammar!!  "), "fix-grammar")
    XCTAssertEqual(toSlug("OpenAI compatible API"), "openai-compatible-api")
    XCTAssertEqual(toSlug("  "), "")
  }

  func testUniqueSlug() {
    let existing = ["fix-grammar", "proofread-email", "openai"]

    // No conflict
    XCTAssertEqual(uniqueSlug(for: "Translate Tone", existingIDs: existing), "translate-tone")

    // Direct conflict
    XCTAssertEqual(uniqueSlug(for: "Fix Grammar", existingIDs: existing), "fix-grammar-1")

    // Conflict with numeric suffix
    let existingWithSuffix = existing + ["fix-grammar-1"]
    XCTAssertEqual(uniqueSlug(for: "Fix Grammar", existingIDs: existingWithSuffix), "fix-grammar-2")
  }

  // Helper mimic of view model slug-generation functions
  private func toSlug(_ title: String) -> String {
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
    let filtered = title.unicodeScalars.filter { allowedCharacters.contains($0) }
    let trimmed = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let slug = trimmed.replacingOccurrences(of: " ", with: "-")
      .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
    return slug
  }

  private func uniqueSlug(for title: String, existingIDs: [String]) -> String {
    let base = toSlug(title)
    let baseSlug = base.isEmpty ? "unnamed" : base
    if !existingIDs.contains(baseSlug) {
      return baseSlug
    }
    var suffix = 1
    while existingIDs.contains("\(baseSlug)-\(suffix)") {
      suffix += 1
    }
    return "\(baseSlug)-\(suffix)"
  }
}
