import XCTest
@testable import TypoFixr

final class KeyboardShortcutTests: XCTestCase {
    
    // MARK: - Reserved Shortcut Tests
    
    func testReservedShortcutCopy() {
        let isReserved = HotkeyService.isReservedShortcut(8, modifiers: [.command])
        XCTAssertTrue(isReserved, "Cmd+C should be reserved")
    }
    
    func testReservedShortcutPaste() {
        // Cmd+V should be reserved
        let isReserved = HotkeyService.isReservedShortcut(9, modifiers: [.command])
        XCTAssertTrue(isReserved, "Cmd+V should be reserved")
    }
    
    func testReservedShortcutUndo() {
        // Cmd+Z should be reserved
        let isReserved = HotkeyService.isReservedShortcut(6, modifiers: [.command])
        XCTAssertTrue(isReserved, "Cmd+Z should be reserved")
    }
    
    func testReservedShortcutQuit() {
        // Cmd+Q should be reserved
        let isReserved = HotkeyService.isReservedShortcut(12, modifiers: [.command])
        XCTAssertTrue(isReserved, "Cmd+Q should be reserved")
    }
    
    func testNonReservedShortcut() {
        // Cmd+Shift+. should NOT be reserved (our default)
        let isReserved = HotkeyService.isReservedShortcut(47, modifiers: [.command, .shift])
        XCTAssertFalse(isReserved, "Cmd+Shift+. should not be reserved")
    }
    
    func testNonReservedCustomShortcut() {
        // Cmd+Shift+F should NOT be reserved
        let isReserved = HotkeyService.isReservedShortcut(3, modifiers: [.command, .shift])
        XCTAssertFalse(isReserved, "Cmd+Shift+F should not be reserved")
    }
    
    // MARK: - Shortcut Display String Tests
    
    func testDisplayStringWithAllModifiers() {
        let shortcut = KeyboardShortcutConfig(
            keyCode: 0, // A
            modifiers: [.command, .shift, .option, .control]
        )
        
        // Should contain all modifier symbols
        XCTAssertTrue(shortcut.displayString.contains("⌘"))
        XCTAssertTrue(shortcut.displayString.contains("⇧"))
        XCTAssertTrue(shortcut.displayString.contains("⌥"))
        XCTAssertTrue(shortcut.displayString.contains("⌃"))
        XCTAssertTrue(shortcut.displayString.contains("A"))
    }
    
    func testDisplayStringCommandOnly() {
        let shortcut = KeyboardShortcutConfig(
            keyCode: 8, // C
            modifiers: [.command]
        )
        
        XCTAssertEqual(shortcut.displayString, "⌘C")
    }
    
    // MARK: - Shortcut Encoding/Decoding Tests
    
    func testShortcutCodable() throws {
        let original = KeyboardShortcutConfig(
            keyCode: 47,
            modifiers: [.command, .shift]
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyboardShortcutConfig.self, from: encoded)
        
        XCTAssertEqual(original, decoded)
    }
}
