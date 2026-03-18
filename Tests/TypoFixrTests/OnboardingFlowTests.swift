import XCTest
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
}
