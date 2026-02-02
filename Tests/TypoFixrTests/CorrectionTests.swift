import XCTest
@testable import TypoFixr

final class CorrectionTests: XCTestCase {
    
    // MARK: - Basic Model Tests
    
    func testCorrectionCreation() {
        let correction = Correction(
            originalText: "teh",
            correctedText: "the"
        )
        
        XCTAssertEqual(correction.originalText, "teh")
        XCTAssertEqual(correction.correctedText, "the")
        XCTAssertFalse(correction.reverted)
    }
    
    func testCorrectionTruncation() {
        // Test truncation for long text
        let longText = String(repeating: "a", count: 100)
        let correction = Correction(
            originalText: longText,
            correctedText: longText
        )
        
        XCTAssertEqual(correction.truncatedOriginal.count, 53) // 50 + "..."
        XCTAssertTrue(correction.truncatedOriginal.hasSuffix("..."))
    }
    
    func testCorrectionShortTextNotTruncated() {
        let shortText = "hello"
        let correction = Correction(
            originalText: shortText,
            correctedText: shortText
        )
        
        XCTAssertEqual(correction.truncatedOriginal, shortText)
        XCTAssertFalse(correction.truncatedOriginal.hasSuffix("..."))
    }
    
    // MARK: - Formatting Preservation Tests
    
    func testLineBreaksInCorrection() {
        let textWithLineBreaks = "line1\nline2\nline3"
        let correction = Correction(
            originalText: textWithLineBreaks,
            correctedText: textWithLineBreaks
        )
        
        XCTAssertTrue(correction.originalText.contains("\n"))
        XCTAssertEqual(correction.originalText.components(separatedBy: "\n").count, 3)
    }
}
