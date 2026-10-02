import XCTest
@testable import TypoFixr

final class WhitespaceNormalizationTests: XCTestCase {
    func testBoundaryWhitespaceDoesNotCountAsACorrection() {
        for original in ["hello world ", " hello world", "hello world\n\n", "  hello world \n\t"] {
            XCTAssertTrue(TextCorrectionService.textIsUnchanged(original: original, corrected: "hello world"))
        }
    }

    func testActualTextChangesAreDetected() {
        for (original, corrected) in [("teh quick brown", "the quick brown"), ("hello  world", "hello world"),
                                      ("your going", "you're going"), ("Hello world", "Hello, world")] {
            XCTAssertFalse(TextCorrectionService.textIsUnchanged(original: original, corrected: corrected))
        }
    }

    func testBoundaryWhitespaceAndAngleBracketsSurviveReplacement() {
        XCTAssertEqual(TextCorrectionService.preservingBoundaryWhitespace(original: "\tContcat <a@b.com>\n\n",
                                                                          corrected: "Contact <a@b.com>"),
                       "\tContact <a@b.com>\n\n")
    }

    func testEmojiPreservedByReplacement() {
        XCTAssertEqual(TextCorrectionService.preservingBoundaryWhitespace(original: "Helo 👩‍💻 ", corrected: "Hello 👩‍💻"), "Hello 👩‍💻 ")
    }
}
