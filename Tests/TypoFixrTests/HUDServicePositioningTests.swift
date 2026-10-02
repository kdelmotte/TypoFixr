import XCTest
import AppKit
import SwiftUI
@testable import TypoFixr

final class HUDServicePositioningTests: XCTestCase {
    func testBottomCenterPlacementOnStandardFrame() {
        let origin = HUDService.hudOrigin(
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowSize: CGSize(width: 280, height: 72),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )

        XCTAssertEqual(origin.x, 580)
        XCTAssertEqual(origin.y, 28)
    }

    func testBottomCenterPlacementRespectsNegativeMinX() {
        let origin = HUDService.hudOrigin(
            visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            windowSize: CGSize(width: 300, height: 60),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )

        XCTAssertEqual(origin.x, -1110)
        XCTAssertEqual(origin.y, 28)
    }

    func testHorizontalClampWhenWindowNearOrWiderThanVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 320, height: 500)

        let nearWidthOrigin = HUDService.hudOrigin(
            visibleFrame: visibleFrame,
            windowSize: CGSize(width: 300, height: 60),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )
        XCTAssertEqual(nearWidthOrigin.x, 110)

        let widerOrigin = HUDService.hudOrigin(
            visibleFrame: visibleFrame,
            windowSize: CGSize(width: 360, height: 60),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )
        XCTAssertEqual(widerOrigin.x, 100)
    }

    func testBottomMarginAppliedCorrectly() {
        let origin = HUDService.hudOrigin(
            visibleFrame: CGRect(x: 0, y: 40, width: 1280, height: 760),
            windowSize: CGSize(width: 260, height: 68),
            bottomMargin: 28,
            horizontalSafetyMargin: 12
        )

        XCTAssertEqual(origin.y, 68)
    }
}


final class UILayoutTests: XCTestCase {
    @MainActor
    func testLoadingAndUndoSubtitlesHaveRoomAtThePresentedWidth() {
        for (title, subtitle) in [("Checking text…", "Keep your selection in place."), ("Fixed", "Press ⌘Z to undo.")] {
            let host = HUDService.makeHostingView(for: HUDView(icon: "checkmark.circle.fill", title: title,
                subtitle: subtitle, isSuccess: true), availableWidth: 1440)
            let textWidth = host.frame.width - 32 - 36 - 12
            let required = (subtitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            XCTAssertGreaterThanOrEqual(textWidth, required, "\(subtitle) must fit without truncation")
            XCTAssertGreaterThanOrEqual(host.frame.height, 68)
        }
    }

    @MainActor
    func testLongHUDMessagesWrapAndGrowInsteadOfWideningOffScreen() {
        let short = HUDService.makeHostingView(for: HUDView(icon: "checkmark.circle.fill", title: "Fixed",
            subtitle: "Press ⌘Z to undo.", isSuccess: true), availableWidth: 1440)
        let message = "The selected text changed while the correction was running. Select the text again, keep the same field focused, and retry when you’re ready."
        let long = HUDService.makeHostingView(for: HUDView(icon: "exclamationmark.circle.fill", title: "Correction stopped",
            subtitle: message, isSuccess: false), availableWidth: 1440)
        let narrow = HUDService.makeHostingView(for: HUDView(icon: "exclamationmark.circle.fill", title: "Correction stopped",
            subtitle: message, isSuccess: false), availableWidth: 240)
        XCTAssertEqual(short.frame.width, long.frame.width)
        XCTAssertGreaterThan(long.frame.height, short.frame.height + 20)
        XCTAssertLessThanOrEqual(narrow.frame.width, 216)
        XCTAssertGreaterThan(narrow.frame.height, long.frame.height)
    }

    @MainActor
    func testReusingSmallWindowPreservesMeasuredHUDSizeAndCannotTakeFocus() {
        let panel = HUDService.createHUDWindow()
        panel.setContentSize(NSSize(width: 90, height: 30))
        for subtitle in ["Keep your selection in place.", "Press ⌘Z to undo."] {
            let host = HUDService.makeHostingView(for: HUDView(icon: "checkmark.circle.fill", title: "Status",
                subtitle: subtitle, isSuccess: true), availableWidth: 1440)
            let expected = host.frame.size
            panel.contentView = host
            panel.setContentSize(expected)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.frame.size, expected)
        }
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.ignoresMouseEvents)
    }

    func testErrorMessagesRemainVisibleLongEnoughToRead() {
        XCTAssertEqual(HUDService.displayDuration(subtitle: "Press ⌘Z to undo.", isSuccess: true), 2.5)
        XCTAssertGreaterThanOrEqual(HUDService.displayDuration(subtitle: "No internet connection", isSuccess: false), 5)
        XCTAssertEqual(HUDService.displayDuration(subtitle: String(repeating: "x", count: 500), isSuccess: false), 10)
    }

    @MainActor
    func testTallMenuIsBoundedByTheVisibleDisplay() {
        let size = AppDelegate.menuPopoverSize(contentHeight: 950, visibleHeight: 600)
        XCTAssertEqual(size.width, MenuBarView.width)
        XCTAssertLessThanOrEqual(size.height, 552)
        XCTAssertEqual(AppDelegate.menuPopoverSize(contentHeight: 300, visibleHeight: 900).height, 300)
    }

    @MainActor
    func testRepresentativeLayoutsAndOptionalReviewSnapshots() throws {
        let environment = try TestEnvironment()
        let state = environment.makeAppState()
        state.hasAccessibilityPermission = true
        state.groqApiKey = "gsk_" + String(repeating: "a", count: 52)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for (label, title, subtitle, success, loading) in [
                ("checking", "Checking text…", "Keep your selection in place.", true, true),
                ("fixed", "Fixed", "Press ⌘Z to undo.", true, false),
                ("error", "Correction stopped", "The selected text changed while checking. Select it again and keep the same field focused until the correction is finished.", false, false)
            ] {
                let host = HUDService.makeHostingView(for: HUDView(icon: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    title: title, subtitle: subtitle, isSuccess: success, isLoading: loading), availableWidth: 1440)
                try snapshot(host, size: host.frame.size, appearance: appearance, name: "hud-\(label)-\(suffix)")
            }
            for step in OnboardingStep.allCases {
                let snapshotState = OnboardingContentSnapshot.measurement(for: step, usesCompactAccessibilityLayout: false)
                let shell = OnboardingShell(step: step, snapshot: snapshotState, apiKeyText: .constant(""),
                    primaryButtonTitle: step.primaryButtonTitle(hasAccessibilityPermission: false),
                    isPrimaryButtonDisabled: step == .apiKey, footerHint: step.footerHint(hasAccessibilityPermission: false),
                    onBack: step == .welcome ? nil : {}, onPrimaryAction: {}, onToggleAPIKeyVisibility: {}, fillsWindowHeight: false)
                let controller = NSHostingController(rootView: shell)
                let size = controller.sizeThatFits(in: CGSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
                try snapshot(NSHostingView(rootView: shell), size: size, appearance: appearance, name: "onboarding-\(step.rawValue)-\(suffix)")
            }
            let menu = NSHostingController(rootView: MenuBarView(scrollsContent: false).environmentObject(state))
            let size = menu.sizeThatFits(in: CGSize(width: MenuBarView.width, height: CGFloat.greatestFiniteMagnitude))
            XCTAssertGreaterThan(size.height, 200)
            XCTAssertLessThan(size.height, 680)
            try snapshot(NSHostingView(rootView: MenuBarView(scrollsContent: false).environmentObject(state)),
                         size: size, appearance: appearance, name: "menu-empty-\(suffix)")
            for section in [SettingsSection.general, .shortcut, .api, .privacy, .about] {
                try snapshot(NSHostingView(rootView: SettingsView(initialSection: section).environmentObject(state)),
                    size: CGSize(width: 600, height: 520), appearance: appearance, name: "settings-\(section.rawValue)-\(suffix)")
            }
        }
        let correction = Correction(originalText: "I cant find the documment you shared yesterday. Could you sent it again when you have a moment?",
            correctedText: "I can’t find the document you shared yesterday. Could you send it again when you have a moment?")
        for index in (0..<3).reversed() {
            state.addCorrection(Correction(timestamp: Date().addingTimeInterval(Double(-index * 120)),
                originalText: correction.originalText, correctedText: correction.correctedText))
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for permission in [true, false] {
                state.hasAccessibilityPermission = permission
                let controller = NSHostingController(rootView: MenuBarView(scrollsContent: false).environmentObject(state))
                let size = controller.sizeThatFits(in: CGSize(width: MenuBarView.width, height: CGFloat.greatestFiniteMagnitude))
                let bounded = AppDelegate.menuPopoverSize(contentHeight: size.height, visibleHeight: 800)
                try snapshot(NSHostingView(rootView: MenuBarView().environmentObject(state)), size: bounded,
                             appearance: appearance, name: "menu-history-\(permission ? "ready" : "permission")-\(suffix)")
            }
            try snapshot(NSHostingView(rootView: CorrectionDetailView(correction: correction)),
                         size: CGSize(width: 400, height: 400), appearance: appearance, name: "correction-detail-\(suffix)")
        }
    }

    @MainActor
    private func snapshot<V: View>(_ host: NSHostingView<V>, size: CGSize, appearance: NSAppearance.Name, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["TYPOFIXR_UI_SNAPSHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: appearance)
        defer { NSApp.appearance = previousAppearance }
        let renderHost = NSHostingView(rootView: host.rootView
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: appearance)
        panel.backgroundColor = .windowBackgroundColor
        renderHost.sizingOptions = []
        renderHost.frame = CGRect(origin: .zero, size: size)
        panel.contentView = renderHost
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        panel.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        renderHost.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(renderHost.bitmapImageRepForCachingDisplay(in: renderHost.bounds))
        panel.appearance?.performAsCurrentDrawingAppearance {
            renderHost.cacheDisplay(in: renderHost.bounds, to: bitmap)
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        panel.orderOut(nil)
    }
}
