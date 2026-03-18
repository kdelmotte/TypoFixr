import XCTest
@testable import TypoFixr

final class TelemetryServiceTests: XCTestCase {

    func testShortcutChangedPayloadMarksDefaultShortcut() {
        let payload = TelemetrySignal.shortcutChanged(isDefault: true).payload

        XCTAssertEqual(payload.name, "Shortcut.changed")
        XCTAssertEqual(payload.parameters, ["is_default": "true"])
    }

    func testCorrectionFailedPayloadIncludesSelectionSourceWhenAvailable() {
        let payload = TelemetrySignal.correctionFailed(
            reason: .rateLimited,
            selectionSource: .paragraphFallback
        ).payload

        XCTAssertEqual(payload.name, "Correction.failed")
        XCTAssertEqual(
            payload.parameters,
            [
                "reason": "rate_limited",
                "selection_source": "paragraph_fallback"
            ]
        )
    }

    func testSecurityWarningPayloadUsesWarningKind() {
        let payload = TelemetrySignal.securityWarningShown(kind: .promptInjection).payload

        XCTAssertEqual(payload.name, "Security.warningShown")
        XCTAssertEqual(payload.parameters, ["kind": "prompt_injection"])
    }

    func testCorrectionFailureReasonMapsAPIErrorCategories() {
        XCTAssertEqual(CorrectionFailureReason(apiError: .timeout), .timeout)
        XCTAssertEqual(CorrectionFailureReason(apiError: .rateLimited), .rateLimited)
        XCTAssertEqual(
            CorrectionFailureReason(apiError: .networkError(NSError(domain: "test", code: 1))),
            .networkError
        )
        XCTAssertEqual(
            CorrectionFailureReason(apiError: .apiError("Bad request")),
            .apiError
        )
    }
}
