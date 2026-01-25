import XCTest
@testable import TypoFixr

final class CorrectionTests: XCTestCase {
    
    // MARK: - TC-2.1.x Basic Replacement Tests
    
    func testCorrectionCreation() {
        // TC-2.1.1: Simple typo fix - model creation
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
    
    // MARK: - TC-2.3.x Formatting Preservation Tests
    
    func testLineBreaksInCorrection() {
        // TC-2.3.1: Line breaks preserved
        let textWithLineBreaks = "line1\nline2\nline3"
        let correction = Correction(
            originalText: textWithLineBreaks,
            correctedText: textWithLineBreaks
        )
        
        XCTAssertTrue(correction.originalText.contains("\n"))
        XCTAssertEqual(correction.originalText.components(separatedBy: "\n").count, 3)
    }
}
