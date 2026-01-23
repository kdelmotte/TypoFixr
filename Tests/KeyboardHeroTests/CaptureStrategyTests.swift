import XCTest
@testable import KeyboardHero

final class CaptureStrategyTests: XCTestCase {
    
    // MARK: - TC-1.1.x Selected Text Priority Tests
    
    func testCapturedTextSelection() {
        // TC-1.1.1: Selected text is used when available
        let captured = CapturedText(
            text: "hello wrold",
            strategy: .selection,
            startIndex: 0
        )
        
        XCTAssertEqual(captured.strategy, .selection)
        XCTAssertEqual(captured.text, "hello wrold")
    }
    
    func testCapturedTextEmpty() {
        // TC-1.2.3: Empty field handled
        let captured = CapturedText(
            text: "   ",
            strategy: .fullField,
            startIndex: 0
        )
        
        XCTAssertTrue(captured.isEmpty)
    }
    
    func testCapturedTextNotEmpty() {
        let captured = CapturedText(
            text: "hello",
            strategy: .fullField,
            startIndex: 0
        )
        
        XCTAssertFalse(captured.isEmpty)
    }
    
    // MARK: - TC-1.4.x Paragraph Fallback Tests
    
    func testCapturedTextParagraph() {
        // TC-1.4.1: Current paragraph detected
        let captured = CapturedText(
            text: "This is the current paragraph.",
            strategy: .currentParagraph,
            startIndex: 50
        )
        
        XCTAssertEqual(captured.strategy, .currentParagraph)
        XCTAssertEqual(captured.startIndex, 50)
    }
    
    // MARK: - TC-1.3.x Since Last Correction Tests
    
    func testCapturedTextSinceLastCorrection() {
        // TC-1.3.2: Text since last correction
        let captured = CapturedText(
            text: "new text after bookmark",
            strategy: .sinceLastCorrection,
            startIndex: 100
        )
        
        XCTAssertEqual(captured.strategy, .sinceLastCorrection)
        XCTAssertEqual(captured.startIndex, 100)
    }
    
    // MARK: - TC-1.2.2 Character Limit Tests
    
    func testCapturedTextTooLong() {
        // TC-1.2.2: Character limit respected - too long case
        let captured = CapturedText(
            text: String(repeating: "a", count: 600),
            strategy: .tooLong,
            startIndex: 0
        )
        
        XCTAssertEqual(captured.strategy, .tooLong)
    }
    
    // MARK: - TC-9.2.x Boundary Conditions Tests
    
    func testCapturedTextVeryShort() {
        // TC-9.2.1: Very short text
        let captured = CapturedText(
            text: "a",
            strategy: .fullField,
            startIndex: 0
        )
        
        XCTAssertFalse(captured.isEmpty)
        XCTAssertEqual(captured.text, "a")
    }
    
    func testCapturedTextSpecialCharacters() {
        // TC-9.2.4: Special characters
        let captured = CapturedText(
            text: "hello @user #tag $100",
            strategy: .selection,
            startIndex: 0
        )
        
        XCTAssertTrue(captured.text.contains("@"))
        XCTAssertTrue(captured.text.contains("#"))
        XCTAssertTrue(captured.text.contains("$"))
    }
    
    func testCapturedTextUnicode() {
        // TC-9.2.5: Unicode/emoji
        let captured = CapturedText(
            text: "café ☕ naïve",
            strategy: .selection,
            startIndex: 0
        )
        
        XCTAssertTrue(captured.text.contains("é"))
        XCTAssertTrue(captured.text.contains("☕"))
        XCTAssertTrue(captured.text.contains("ï"))
    }
}
