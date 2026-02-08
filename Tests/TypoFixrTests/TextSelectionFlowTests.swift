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
    func testWhitespaceOnlyExistingSelectionFallsThroughToParagraph() async {
        // Simulates checkExistingSelection returning .noSelection for whitespace-only text
        // (e.g. user accidentally selects a trailing space)
        var paragraphCalled = false

        let result = await service.resolveSelectionResult(
            checkExistingSelection: { .noSelection },
            tryParagraphSelection: {
                paragraphCalled = true
                return .success(text: "This is the paragraph.", source: .paragraphFallback)
            },
            tryLineSelection: { .noSelection }
        )

        XCTAssertTrue(paragraphCalled, "Paragraph fallback should run when existing selection is whitespace-only")
        XCTAssertEqual(result, .success(text: "This is the paragraph.", source: .paragraphFallback))
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

    // MARK: - ensureSelectionBeforePaste Tests

    @MainActor
    func testEnsureSelection_SelectionStillActive_NoReselect() async {
        var reSelectCalled = false

        await service.ensureSelectionBeforePaste(
            selectionSource: .paragraphFallback,
            probeSelection: { true },
            reSelect: { reSelectCalled = true }
        )

        XCTAssertFalse(reSelectCalled, "Should not re-select when selection is still active")
    }

    @MainActor
    func testEnsureSelection_SelectionLost_Reselects() async {
        var reSelectCalled = false

        await service.ensureSelectionBeforePaste(
            selectionSource: .paragraphFallback,
            probeSelection: { false },
            reSelect: { reSelectCalled = true }
        )

        XCTAssertTrue(reSelectCalled, "Should re-select when selection is lost")
    }

    @MainActor
    func testEnsureSelection_ExistingSelectionSource_SkipsCheck() async {
        var probeCalled = false
        var reSelectCalled = false

        await service.ensureSelectionBeforePaste(
            selectionSource: .existingSelection,
            probeSelection: {
                probeCalled = true
                return false
            },
            reSelect: { reSelectCalled = true }
        )

        XCTAssertFalse(probeCalled, "Should not probe when source is existingSelection")
        XCTAssertFalse(reSelectCalled, "Should not re-select when source is existingSelection")
    }

    @MainActor
    func testEnsureSelection_LineFallback_SelectionLost_Reselects() async {
        var reSelectCalled = false

        await service.ensureSelectionBeforePaste(
            selectionSource: .lineFallback,
            probeSelection: { false },
            reSelect: { reSelectCalled = true }
        )

        XCTAssertTrue(reSelectCalled, "Should re-select for lineFallback when selection is lost")
    }

    @MainActor
    func testEnsureSelection_LineFallback_SelectionActive_NoReselect() async {
        var reSelectCalled = false

        await service.ensureSelectionBeforePaste(
            selectionSource: .lineFallback,
            probeSelection: { true },
            reSelect: { reSelectCalled = true }
        )

        XCTAssertFalse(reSelectCalled, "Should not re-select for lineFallback when selection is active")
    }

    @MainActor
    func testEnsureSelection_ParagraphFallback_SelectionLost_CallsReselect() async {
        var reSelectArgs: [String] = []

        await service.ensureSelectionBeforePaste(
            selectionSource: .paragraphFallback,
            probeSelection: { false },
            reSelect: { reSelectArgs.append("reselected") }
        )

        XCTAssertEqual(reSelectArgs, ["reselected"], "Should call reSelect exactly once")
    }
}
