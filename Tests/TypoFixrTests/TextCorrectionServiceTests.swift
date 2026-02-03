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
}
