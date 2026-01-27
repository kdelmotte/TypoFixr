import XCTest
@testable import TypoFixr

final class WhitespaceNormalizationTests: XCTestCase {
    
    // MARK: - Trailing/Leading Whitespace Tests
    
    func testTrailingSpaceIgnored() {
        let original = "hello world "
        let corrected = "hello world"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized,
            "Trailing space should not count as a change")
    }
    
    func testLeadingSpaceIgnored() {
        let original = " hello world"
        let corrected = "hello world"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized,
            "Leading space should not count as a change")
    }
    
    func testTrailingNewlineIgnored() {
        let original = "hello world\n"
        let corrected = "hello world"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized,
            "Trailing newline should not count as a change")
    }
    
    func testMultipleTrailingNewlinesIgnored() {
        let original = "hello world\n\n\n"
        let corrected = "hello world"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized,
            "Multiple trailing newlines should not count as a change")
    }
    
    func testMixedWhitespaceIgnored() {
        let original = "  hello world \n\t"
        let corrected = "hello world"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized,
            "Mixed leading/trailing whitespace should not count as a change")
    }
    
    // MARK: - Actual Changes Should Be Detected
    
    func testActualTypoChangeDetected() {
        let original = "teh quick brown"
        let corrected = "the quick brown"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertNotEqual(originalNormalized, correctedNormalized,
            "Actual typo fix should be detected as a change")
    }
    
    func testInternalWhitespaceChangeDetected() {
        let original = "hello  world"  // Two spaces
        let corrected = "hello world"   // One space
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertNotEqual(originalNormalized, correctedNormalized,
            "Internal whitespace changes should be detected")
    }
    
    func testGrammarChangeDetected() {
        let original = "your going to the store"
        let corrected = "you're going to the store"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertNotEqual(originalNormalized, correctedNormalized,
            "Grammar fix should be detected as a change")
    }
    
    func testPunctuationChangeDetected() {
        let original = "Hello world"
        let corrected = "Hello, world"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertNotEqual(originalNormalized, correctedNormalized,
            "Punctuation change should be detected")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStringHandled() {
        let original = ""
        let corrected = ""
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized)
    }
    
    func testWhitespaceOnlyStringHandled() {
        let original = "   \n\t  "
        let corrected = ""
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized,
            "Whitespace-only string should equal empty string after trimming")
    }
    
    func testUnicodePreserved() {
        let original = "Hello 👋 world"
        let corrected = "Hello 👋 world"
        
        let originalNormalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedNormalized = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(originalNormalized, correctedNormalized,
            "Unicode characters should be preserved")
    }
}
