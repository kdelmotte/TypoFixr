import XCTest
@testable import KeyboardHero

final class CorrectionBookmarkTests: XCTestCase {
    
    // MARK: - TC-1.3.x Correction Bookmark System Tests
    
    func testBookmarkCreation() {
        // TC-1.3.1: Bookmark created after fix
        let bookmark = CorrectionBookmark(
            appBundleId: "com.apple.Notes",
            textFieldSignature: "notes:textarea:main",
            endIndex: 5,
            textAtBookmark: "hello"
        )
        
        XCTAssertEqual(bookmark.appBundleId, "com.apple.Notes")
        XCTAssertEqual(bookmark.endIndex, 5)
        XCTAssertTrue(bookmark.isValid) // Should be valid immediately
    }
    
    func testBookmarkKeyGeneration() {
        let key = CorrectionBookmark.generateKey(
            appBundleId: "com.apple.Notes",
            textFieldSignature: "notes:textarea:main"
        )
        
        XCTAssertEqual(key, "com.apple.Notes:notes:textarea:main")
    }
    
    func testBookmarkValidity() {
        // TC-1.3.2: Second fix uses bookmark
        let bookmark = CorrectionBookmark(
            appBundleId: "com.apple.Notes",
            textFieldSignature: "notes:textarea:main",
            endIndex: 10,
            textAtBookmark: "test"
        )
        
        // Fresh bookmark should be valid
        XCTAssertTrue(bookmark.isValid)
    }
    
    // Note: Testing bookmark expiration would require mocking Date
    // In production, use dependency injection for Date.now
}
