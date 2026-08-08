import XCTest
@testable import Overtype

final class SlugGenerationTests: XCTestCase {

    func testToSlug() {
        let viewModel = SettingsViewModel.shared
        XCTAssertEqual(viewModel.toSlug("Translate French"), "translate-french")
        XCTAssertEqual(viewModel.toSlug("  Fix   Grammar!!  "), "fix-grammar")
        XCTAssertEqual(viewModel.toSlug("OpenAI compatible API"), "openai-compatible-api")
        XCTAssertEqual(viewModel.toSlug("  "), "")
    }

    func testUniqueSlug() {
        let viewModel = SettingsViewModel.shared
        let existing = ["fix-grammar", "proofread-email", "openai"]

        // No conflict
        XCTAssertEqual(viewModel.uniqueSlug(for: "Translate Tone", existingIDs: existing), "translate-tone")

        // Direct conflict
        XCTAssertEqual(viewModel.uniqueSlug(for: "Fix Grammar", existingIDs: existing), "fix-grammar-1")

        // Conflict with numeric suffix
        let existingWithSuffix = existing + ["fix-grammar-1"]
        XCTAssertEqual(viewModel.uniqueSlug(for: "Fix Grammar", existingIDs: existingWithSuffix), "fix-grammar-2")
    }
}
