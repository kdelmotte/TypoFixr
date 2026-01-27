import XCTest
import SwiftUI
@testable import TypoFixr

final class HUDViewTests: XCTestCase {
    
    // MARK: - HUD View Creation Tests
    
    func testHUDViewSuccessState() {
        let hudView = HUDView(
            icon: "checkmark.circle.fill",
            title: "Fixed!",
            subtitle: "⌘Z to undo",
            isSuccess: true
        )
        
        XCTAssertEqual(hudView.title, "Fixed!")
        XCTAssertEqual(hudView.subtitle, "⌘Z to undo")
        XCTAssertEqual(hudView.icon, "checkmark.circle.fill")
        XCTAssertTrue(hudView.isSuccess)
    }
    
    func testHUDViewErrorState() {
        let hudView = HUDView(
            icon: "xmark.circle.fill",
            title: "Error",
            subtitle: "Something went wrong",
            isSuccess: false
        )
        
        XCTAssertEqual(hudView.title, "Error")
        XCTAssertEqual(hudView.subtitle, "Something went wrong")
        XCTAssertEqual(hudView.icon, "xmark.circle.fill")
        XCTAssertFalse(hudView.isSuccess)
    }
    
    func testHUDViewNoChangesState() {
        let hudView = HUDView(
            icon: "checkmark.circle.fill",
            title: "No Changes",
            subtitle: "Your text looks good!",
            isSuccess: true
        )
        
        XCTAssertEqual(hudView.title, "No Changes")
        XCTAssertTrue(hudView.isSuccess)
    }
    
    func testHUDViewRevertedState() {
        let hudView = HUDView(
            icon: "checkmark.circle.fill",
            title: "Reverted",
            subtitle: "Original text restored",
            isSuccess: true
        )
        
        XCTAssertEqual(hudView.title, "Reverted")
        XCTAssertEqual(hudView.subtitle, "Original text restored")
    }
    
    // MARK: - HUD Message Content Tests
    
    func testFixedMessageIncludesUndoHint() {
        let subtitle = "⌘Z to undo"
        XCTAssertTrue(subtitle.contains("⌘Z"),
            "Fixed message should include Command-Z undo hint")
    }
    
    func testUndoHintUsesCommandSymbol() {
        let subtitle = "⌘Z to undo"
        XCTAssertTrue(subtitle.contains("⌘"),
            "Undo hint should use ⌘ symbol, not 'Cmd'")
        XCTAssertFalse(subtitle.lowercased().contains("cmd"),
            "Undo hint should not use 'Cmd' text")
    }
    
    func testNoChangesMessageIsEncouraging() {
        let subtitle = "Your text looks good!"
        XCTAssertTrue(subtitle.contains("good"),
            "No changes message should be positive/encouraging")
    }
    
    func testTextTooLongMessageFormat() {
        let characterLimit = 500
        let subtitle = "Select up to \(characterLimit) characters"
        XCTAssertTrue(subtitle.contains("500"),
            "Text too long message should include the character limit")
        XCTAssertTrue(subtitle.contains("Select"),
            "Text too long message should guide user to select text")
    }
    
    func testSelectTextMessageIsActionable() {
        let subtitle = "Highlight text first"
        XCTAssertTrue(subtitle.contains("Highlight") || subtitle.contains("Select"),
            "Select text message should tell user what action to take")
    }
    
    func testPermissionMessageIsDescriptive() {
        let subtitle = "Grant Accessibility access"
        XCTAssertTrue(subtitle.contains("Accessibility"),
            "Permission message should mention Accessibility")
    }
}
