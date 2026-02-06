import XCTest
@testable import TypoFixr

final class TextCorrectionServiceNormalizationTests: XCTestCase {

    func testNotesParagraphFallbackStripsDashChecklistPrefix() {
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: "- [ ] buy milk",
            appBundleId: "com.apple.Notes",
            source: .paragraphFallback
        )

        XCTAssertEqual(normalized, "buy milk")
    }

    func testNotesLineFallbackStripsDashPrefix() {
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: "- buy milk",
            appBundleId: "com.apple.Notes",
            source: .lineFallback
        )

        XCTAssertEqual(normalized, "buy milk")
    }

    func testNotesParagraphFallbackStripsChecklistPrefix() {
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: "[ ] buy milk",
            appBundleId: "com.apple.Notes",
            source: .paragraphFallback
        )

        XCTAssertEqual(normalized, "buy milk")
    }

    func testNotesExistingSelectionPreservesDashPrefix() {
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: "- buy milk",
            appBundleId: "com.apple.Notes",
            source: .existingSelection
        )

        XCTAssertEqual(normalized, "- buy milk")
    }

    func testNonNotesFallbackPreservesDashPrefix() {
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: "- buy milk",
            appBundleId: "com.google.Chrome",
            source: .paragraphFallback
        )

        XCTAssertEqual(normalized, "- buy milk")
    }

    func testNotesFallbackPreservesPlainSentence() {
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: "buy milk today",
            appBundleId: "com.apple.Notes",
            source: .paragraphFallback
        )

        XCTAssertEqual(normalized, "buy milk today")
    }

    // MARK: - Multi-line Notes Text (Bug 3)

    func testNotesMultiLineTextSkipsNormalization() {
        // Multi-line text should be returned unchanged so GroqService's list-aware path handles it
        let text = "- buy milk\n- call mom"
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: text,
            appBundleId: "com.apple.Notes",
            source: .paragraphFallback
        )

        XCTAssertEqual(normalized, "- buy milk\n- call mom")
    }

    func testNotesSingleLineStillStrips() {
        // Single-line Notes text should still strip the bullet prefix
        let normalized = TextCorrectionService.normalizeCapturedTextForCorrection(
            text: "- buy milk",
            appBundleId: "com.apple.Notes",
            source: .paragraphFallback
        )

        XCTAssertEqual(normalized, "buy milk")
    }
}
