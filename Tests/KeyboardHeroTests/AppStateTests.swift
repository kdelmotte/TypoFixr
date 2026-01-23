import XCTest
@testable import KeyboardHero

final class AppStateTests: XCTestCase {
    
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    // MARK: - TC-3.2.x History-Based Revert Tests
    
    func testHistoryStoresCorrections() {
        // TC-3.2.1: History stores corrections
        let correction1 = Correction(
            originalText: "teh",
            correctedText: "the"
        )
        let correction2 = Correction(
            originalText: "wrold",
            correctedText: "world"
        )
        let correction3 = Correction(
            originalText: "helo",
            correctedText: "hello"
        )
        
        appState.addCorrection(correction1)
        appState.addCorrection(correction2)
        appState.addCorrection(correction3)
        
        XCTAssertEqual(appState.correctionHistory.count, 3)
    }
    
    func testHistoryLimitRespected() {
        // TC-3.2.3: History limit respected
        for i in 0..<15 {
            let correction = Correction(
                originalText: "text\(i)",
                correctedText: "fixed\(i)"
            )
            appState.addCorrection(correction)
        }
        
        XCTAssertEqual(appState.correctionHistory.count, 10)
    }
    
    func testHistoryOrderMostRecentFirst() {
        let correction1 = Correction(
            originalText: "first",
            correctedText: "FIRST"
        )
        let correction2 = Correction(
            originalText: "second",
            correctedText: "SECOND"
        )
        
        appState.addCorrection(correction1)
        appState.addCorrection(correction2)
        
        // Most recent should be first
        XCTAssertEqual(appState.correctionHistory.first?.originalText, "second")
    }
    
    // MARK: - TC-3.1.x Toggle Revert Tests
    
    func testRevertWindowActivation() {
        // TC-3.1.1: Revert within window
        let correction = Correction(
            originalText: "test",
            correctedText: "TEST"
        )
        
        appState.addCorrection(correction)
        
        // Should be able to revert immediately after correction
        XCTAssertTrue(appState.canToggleRevert)
    }
    
    func testRevertCorrection() {
        // TC-3.2.2: Revert from history
        let correction = Correction(
            originalText: "test",
            correctedText: "TEST"
        )
        
        appState.addCorrection(correction)
        appState.revertCorrection(correction)
        
        // Find the correction in history and check it's marked as reverted
        let revertedCorrection = appState.correctionHistory.first(where: { $0.id == correction.id })
        XCTAssertTrue(revertedCorrection?.reverted ?? false)
    }
    
    // MARK: - Bookmark Management Tests
    
    func testBookmarkStorage() {
        let bookmark = CorrectionBookmark(
            appBundleId: "com.test.app",
            textFieldSignature: "main:textfield",
            endIndex: 10,
            textAtBookmark: "text"
        )
        
        let key = CorrectionBookmark.generateKey(
            appBundleId: "com.test.app",
            textFieldSignature: "main:textfield"
        )
        
        appState.setBookmark(for: key, bookmark: bookmark)
        
        let retrieved = appState.getBookmark(for: key)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.endIndex, 10)
    }
    
    func testBookmarkClearing() {
        let bookmark = CorrectionBookmark(
            appBundleId: "com.test.app",
            textFieldSignature: "main:textfield",
            endIndex: 10,
            textAtBookmark: "text"
        )
        
        let key = "com.test.app:main:textfield"
        
        appState.setBookmark(for: key, bookmark: bookmark)
        appState.clearBookmark(for: key)
        
        let retrieved = appState.getBookmark(for: key)
        XCTAssertNil(retrieved)
    }
    
    // MARK: - TC-4.2.x Custom Shortcut Tests
    
    func testShortcutConfiguration() {
        // TC-4.2.1: Can change shortcut
        let newShortcut = KeyboardShortcutConfig(
            keyCode: 3, // F key
            modifiers: [.command, .shift]
        )
        
        appState.keyboardShortcut = newShortcut
        
        XCTAssertEqual(appState.keyboardShortcut.keyCode, 3)
        XCTAssertTrue(appState.keyboardShortcut.modifiers.contains(.command))
        XCTAssertTrue(appState.keyboardShortcut.modifiers.contains(.shift))
    }
    
    func testShortcutDisplayString() {
        let shortcut = KeyboardShortcutConfig(
            keyCode: 47, // Period
            modifiers: [.command, .shift]
        )
        
        XCTAssertEqual(shortcut.displayString, "⇧⌘.")
    }
}
