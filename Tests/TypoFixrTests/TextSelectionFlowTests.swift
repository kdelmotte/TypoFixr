import XCTest
@testable import TypoFixr

final class TextSelectionFlowTests: XCTestCase {
    private var appState: AppState!
    private var service: TextCorrectionService!

    override func setUp() {
        super.setUp()
        appState = AppState()
        service = TextCorrectionService(appState: appState)
    }

    override func tearDown() {
        service = nil
        appState = nil
        super.tearDown()
    }

    @MainActor
    func testExistingSelectionSuccessSkipsFallbacks() async {
        var paragraphCalled = false
        var lineCalled = false

        let result = await service.resolveSelectionResult(
            checkExistingSelection: {
                .success(text: "manual", source: .existingSelection)
            },
            tryParagraphSelection: {
                paragraphCalled = true
                return .success(text: "paragraph", source: .paragraphFallback)
            },
            tryLineSelection: {
                lineCalled = true
                return .success(text: "line", source: .lineFallback)
            }
        )

        XCTAssertEqual(result, .success(text: "manual", source: .existingSelection))
        XCTAssertFalse(paragraphCalled)
        XCTAssertFalse(lineCalled)
    }

    @MainActor
    func testParagraphFallbackRunsAfterNoSelection() async {
        var lineCalled = false

        let result = await service.resolveSelectionResult(
            checkExistingSelection: { .noSelection },
            tryParagraphSelection: { .success(text: "paragraph", source: .paragraphFallback) },
            tryLineSelection: {
                lineCalled = true
                return .success(text: "line", source: .lineFallback)
            }
        )

        XCTAssertEqual(result, .success(text: "paragraph", source: .paragraphFallback))
        XCTAssertFalse(lineCalled)
    }

    @MainActor
    func testLineFallbackRunsAfterParagraphNoSelection() async {
        let result = await service.resolveSelectionResult(
            checkExistingSelection: { .noSelection },
            tryParagraphSelection: { .noSelection },
            tryLineSelection: { .success(text: "line", source: .lineFallback) }
        )

        XCTAssertEqual(result, .success(text: "line", source: .lineFallback))
    }

    @MainActor
    func testNoSelectionReturnedAfterAllStrategiesFail() async {
        let result = await service.resolveSelectionResult(
            checkExistingSelection: { .noSelection },
            tryParagraphSelection: { .noSelection },
            tryLineSelection: { .noSelection }
        )

        XCTAssertEqual(result, .noSelection)
    }

    @MainActor
    func testTooLongShortCircuitsWithoutFallbacks() async {
        var paragraphCalled = false
        var lineCalled = false

        let result = await service.resolveSelectionResult(
            checkExistingSelection: {
                .tooLong(selected: String(repeating: "a", count: AppState.characterLimit + 1))
            },
            tryParagraphSelection: {
                paragraphCalled = true
                return .noSelection
            },
            tryLineSelection: {
                lineCalled = true
                return .noSelection
            }
        )

        if case .tooLong = result {
            // expected
        } else {
            XCTFail("Expected .tooLong result")
        }

        XCTAssertFalse(paragraphCalled)
        XCTAssertFalse(lineCalled)
    }

    @MainActor
    func testSelectionStrategiesRunInOrder() async {
        var attempts: [String] = []

        let result = await service.resolveSelectionResult(
            checkExistingSelection: {
                attempts.append("existing")
                return .noSelection
            },
            tryParagraphSelection: {
                attempts.append("paragraph")
                return .noSelection
            },
            tryLineSelection: {
                attempts.append("line")
                return .success(text: "line", source: .lineFallback)
            }
        )

        XCTAssertEqual(attempts, ["existing", "paragraph", "line"])
        XCTAssertEqual(result, .success(text: "line", source: .lineFallback))
    }
}
