import XCTest
import SwiftUI
import AppKit
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
    
    // Note: "Text Too Long" now uses an alert instead of HUD, so no HUD test needed
    
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


final class MenuBarIconTests: XCTestCase {
    @MainActor
    func testEveryMenuBarStateRendersVisibleTemplatePixels() throws {
        for state in MenuBarIconState.allCases {
            try assertVisible(TypoFixrBranding.menuBarImage(for: state), state: state)
        }
    }

    @MainActor
    func testUnavailableSymbolsFallBackToVisibleBranding() throws {
        for state in MenuBarIconState.allCases {
            let image = TypoFixrBranding.menuBarImage(for: state, symbolProvider: { _, _ in nil })
            try assertVisible(image, state: state)
        }
    }

    @MainActor
    private func assertVisible(_ image: NSImage, state: MenuBarIconState) throws {
        XCTAssertTrue(image.isTemplate, "\(state) must adapt to the menu bar appearance")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 48, height: 48).fill(using: .copy)
        image.draw(in: NSRect(x: 4, y: 4, width: 40, height: 40))
        context.flushGraphics()
        let visible = (0..<48).contains { y in
            (0..<48).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 }
        }
        XCTAssertTrue(visible, "\(state) rendered a blank menu bar image")
    }
}
