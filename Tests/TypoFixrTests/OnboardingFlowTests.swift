import XCTest
import SwiftUI
import AppKit
@testable import TypoFixr

final class OnboardingFlowTests: XCTestCase {
    func testWelcomeStepAlwaysAllowsContinue() {
        let state = OnboardingGateState(
            hasAccessibilityPermission: false,
            apiKeyValidationState: .empty
        )

        XCTAssertTrue(state.canContinue(from: .welcome))
    }

    func testAccessibilityStepRequiresPermission() {
        let blocked = OnboardingGateState(
            hasAccessibilityPermission: false,
            apiKeyValidationState: .valid
        )
        let allowed = OnboardingGateState(
            hasAccessibilityPermission: true,
            apiKeyValidationState: .empty
        )

        XCTAssertFalse(blocked.canContinue(from: .accessibility))
        XCTAssertTrue(allowed.canContinue(from: .accessibility))
    }

    func testAPIKeyStepBlocksWhenKeyIsEmpty() {
        let state = OnboardingGateState(
            hasAccessibilityPermission: true,
            apiKeyValidationState: GroqAPIKeyValidationState(apiKey: "")
        )

        XCTAssertFalse(state.canContinue(from: .apiKey))
    }

    func testAPIKeyStepBlocksWhenKeyIsMalformed() {
        let state = OnboardingGateState(
            hasAccessibilityPermission: true,
            apiKeyValidationState: GroqAPIKeyValidationState(apiKey: "abc123")
        )

        XCTAssertFalse(state.canContinue(from: .apiKey))
    }

    func testAPIKeyStepAllowsWhenKeyHasGroqPrefix() {
        let state = OnboardingGateState(
            hasAccessibilityPermission: true,
            apiKeyValidationState: GroqAPIKeyValidationState(apiKey: "gsk_live_123456789")
        )

        XCTAssertTrue(state.canContinue(from: .apiKey))
    }

    func testAPIKeyStepBlocksExamplePlaceholderValue() {
        let state = OnboardingGateState(
            hasAccessibilityPermission: true,
            apiKeyValidationState: GroqAPIKeyValidationState(apiKey: "gsk_...")
        )

        XCTAssertFalse(state.canContinue(from: .apiKey))
    }

    func testSanitizedPersistedAPIKeyClearsObviousExampleValues() {
        XCTAssertEqual(GroqAPIKeyValidationState.sanitizedPersistedAPIKey("gsk_..."), "")
        XCTAssertEqual(GroqAPIKeyValidationState.sanitizedPersistedAPIKey("gsk_test_key"), "")
    }

    func testOnboardingWindowSizerKeepsPreferredWidthWhenTallestStepFits() {
        let layout = OnboardingWindowSizer.resolveLayout(
            for: CGRect(x: 0, y: 0, width: 1440, height: 900)
        ) { step, width, usesCompactAccessibilityLayout in
            XCTAssertFalse(usesCompactAccessibilityLayout)
            XCTAssertEqual(width, 640, accuracy: 0.1)

            if step == .accessibility {
                return 520
            }

            return 460
        }

        XCTAssertEqual(layout.size.width, 640, accuracy: 0.1)
        XCTAssertEqual(layout.size.height, 520, accuracy: 0.1)
        XCTAssertFalse(layout.usesCompactAccessibilityLayout)
    }

    func testOnboardingWindowSizerWidensBeforeSwitchingToCompactAccessibilityLayout() {
        let layout = OnboardingWindowSizer.resolveLayout(
            for: CGRect(x: 0, y: 0, width: 1440, height: 760)
        ) { step, width, usesCompactAccessibilityLayout in
            XCTAssertFalse(usesCompactAccessibilityLayout)

            if width < 680 {
                return step == .accessibility ? 710 : 520
            }

            return step == .accessibility ? 620 : 500
        }

        XCTAssertEqual(layout.size.width, 680, accuracy: 0.1)
        XCTAssertEqual(layout.size.height, 620, accuracy: 0.1)
        XCTAssertFalse(layout.usesCompactAccessibilityLayout)
    }

    func testOnboardingWindowSizerUsesCompactAccessibilityLayoutAsLastStep() {
        let layout = OnboardingWindowSizer.resolveLayout(
            for: CGRect(x: 0, y: 0, width: 1440, height: 740)
        ) { step, width, usesCompactAccessibilityLayout in
            if usesCompactAccessibilityLayout {
                return step == .accessibility ? 620 : 500
            }

            if width < 680 {
                return step == .accessibility ? 760 : 520
            }

            return step == .accessibility ? 710 : 520
        }

        XCTAssertEqual(layout.size.width, 680, accuracy: 0.1)
        XCTAssertEqual(layout.size.height, 620, accuracy: 0.1)
        XCTAssertTrue(layout.usesCompactAccessibilityLayout)
    }

    @MainActor
    func testMeasuredOnboardingShellFitsAllStepsWithinResolvedWindowHeight() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let layout = OnboardingWindowSizer.resolveLayout(for: visibleFrame) { step, width, usesCompactAccessibilityLayout in
            self.measureShellHeight(
                step: step,
                width: width,
                usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
            )
        }

        for step in OnboardingStep.allCases {
            let measuredHeight = measureShellHeight(
                step: step,
                width: layout.size.width,
                usesCompactAccessibilityLayout: layout.usesCompactAccessibilityLayout
            )
            XCTAssertLessThanOrEqual(measuredHeight, layout.size.height + 1)
        }
    }

    @MainActor
    private func measureShellHeight(
        step: OnboardingStep,
        width: CGFloat,
        usesCompactAccessibilityLayout: Bool
    ) -> CGFloat {
        let snapshot = OnboardingContentSnapshot.measurement(
            for: step,
            usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
        )
        let shell = OnboardingShell(
            step: step,
            snapshot: snapshot,
            apiKeyText: .constant(snapshot.apiKey),
            primaryButtonTitle: step.primaryButtonTitle(
                hasAccessibilityPermission: snapshot.hasAccessibilityPermission
            ),
            isPrimaryButtonDisabled: step == .apiKey && snapshot.apiKeyValidationState != .valid,
            footerHint: step.footerHint(
                hasAccessibilityPermission: snapshot.hasAccessibilityPermission
            ),
            onBack: step.previous == nil ? nil : {},
            onPrimaryAction: {},
            onToggleAPIKeyVisibility: {},
            fillsWindowHeight: false
        )

        let controller = NSHostingController(rootView: shell)
        if #available(macOS 13.0, *) {
            controller.sizingOptions = []
        }

        return controller.sizeThatFits(
            in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ).height
    }
}
