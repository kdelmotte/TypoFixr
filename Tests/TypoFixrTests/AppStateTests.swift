import XCTest
@testable import TypoFixr

final class AppStateTests: XCTestCase {
    
    var appState: AppState!
    private var environment: TestEnvironment!
    
    override func setUpWithError() throws {
        environment = try TestEnvironment()
        appState = environment.makeAppState()
    }
    
    override func tearDown() {
        appState = nil
        environment = nil
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

    func testClearingOneDatabaseDoesNotAffectAnother() throws {
        let other = try TestEnvironment()
        let otherState = other.makeAppState()
        otherState.addCorrection(Correction(originalText: "kept", correctedText: "Kept"))
        appState.addCorrection(Correction(originalText: "removed", correctedText: "Removed"))
        appState.clearHistory()
        XCTAssertEqual(other.database.getRecentCorrections().count, 1)
        XCTAssertTrue(environment.database.getRecentCorrections().isEmpty)
    }

    func testSettingsAndCredentialsAreIsolated() throws {
        let other = try TestEnvironment()
        appState.keyboardShortcut = KeyboardShortcutConfig(keyCode: 3, modifiers: [.command])
        appState.groqApiKey = "gsk_" + String(repeating: "a", count: 52)
        XCTAssertNil(other.defaults.data(forKey: "keyboardShortcut"))
        XCTAssertNil(try other.credentials.load(key: "groq_api_key"))
        XCTAssertEqual(try environment.credentials.load(key: "groq_api_key"), appState.groqApiKey)
    }
}
