import XCTest
@testable import TypoFixr

final class AppStateTests: XCTestCase {
    
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        // Tests should not depend on persisted local history.
        appState.clearHistory()
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    // MARK: - History Tests
    
    func testHistoryStoresCorrections() {
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
    
    // MARK: - Revert Tests
    
    func testRevertMarksCorrectionAsReverted() {
        let correction = Correction(
            originalText: "teh",
            correctedText: "the"
        )
        
        appState.addCorrection(correction)
        appState.revertCorrection(correction)
        
        XCTAssertEqual(appState.correctionHistory.first?.id, correction.id)
        XCTAssertEqual(appState.correctionHistory.first?.reverted, true)
    }
    
    // MARK: - Shortcut Tests
    
    func testShortcutConfiguration() {
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
