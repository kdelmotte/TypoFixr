import XCTest
@testable import TypoFixr

private actor SuspendedCorrector: TextCorrecting {
    private(set) var callCount = 0
    private var result: CheckedContinuation<GroqService.CorrectionResult, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func correctText(_ text: String, apiKey: String, languagePreference: String) async throws -> GroqService.CorrectionResult {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            result = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if result != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ text: String = "the text") {
        result?.resume(returning: .init(correctedText: text, inputTokens: 2, outputTokens: 2))
        result = nil
    }
    func fail() {
        result?.resume(throwing: GroqService.APIError.timeout)
        result = nil
    }
}

@MainActor
private final class TestEditor: CorrectionTextEditing {
    var current = true
    var captureCount = 0
    var replacements: [String] = []
    var ended = false
    var rejectAtPaste = false
    var selection = CapturedSelection(text: "teh text", source: .existingSelection, appBundleID: "test.editor")

    func captureSelection(characterLimit: Int) async throws -> CapturedSelection { captureCount += 1; return selection }
    func isSelectionCurrent(_ selection: CapturedSelection) -> Bool { current }
    func replaceSelection(_ selection: CapturedSelection, with text: String) async throws {
        guard current, !rejectAtPaste else { throw TextEditingError.destinationChanged }
        replacements.append(text)
    }
    func endSession() { ended = true }
}

final class TextSelectionFlowTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (TestEnvironment, AppState, TestEditor, SuspendedCorrector, TextCorrectionService) {
        let environment = try TestEnvironment()
        let state = environment.makeAppState()
        state.hasAccessibilityPermission = true
        state.groqApiKey = "test-key"
        state.securityWarningsEnabled = false
        let editor = TestEditor()
        let api = SuspendedCorrector()
        let feedback = CorrectionFeedback(message: { _, _, _ in }, loading: {}, confirmSensitive: { _, _ in false })
        let service = TextCorrectionService(appState: state, corrector: api, editor: editor, isConnected: { true }, feedback: feedback)
        return (environment, state, editor, api, service)
    }

    @MainActor
    func testRepeatedShortcutCannotStartAnotherCorrection() async throws {
        let (environment, state, editor, api, service) = try fixture()
        defer { _ = environment }
        let first = Task { await service.performCorrection() }
        await api.waitUntilStarted()
        await service.performCorrection()
        XCTAssertTrue(state.isProcessing)
        XCTAssertEqual(editor.captureCount, 1)
        let callCount = await api.callCount
        XCTAssertEqual(callCount, 1)
        await api.finish()
        await first.value
        XCTAssertEqual(editor.replacements, ["the text"])
        XCTAssertEqual(state.correctionHistory.count, 1)
        XCTAssertFalse(state.isProcessing)
        XCTAssertTrue(editor.ended)
    }

    @MainActor
    func testChangedDestinationNeverPastesOrLogsSuccess() async throws {
        let (environment, state, editor, api, service) = try fixture()
        defer { _ = environment }
        let task = Task { await service.performCorrection() }
        await api.waitUntilStarted()
        editor.current = false
        await api.finish()
        await task.value
        XCTAssertTrue(editor.replacements.isEmpty)
        XCTAssertTrue(state.correctionHistory.isEmpty)
        XCTAssertNotNil(state.lastError)
        XCTAssertFalse(state.isProcessing)
    }

    @MainActor
    func testChangeImmediatelyBeforePasteDoesNotLogSuccess() async throws {
        let (environment, state, editor, api, service) = try fixture()
        defer { _ = environment }
        let task = Task { await service.performCorrection() }
        await api.waitUntilStarted()
        editor.rejectAtPaste = true
        await api.finish()
        await task.value
        XCTAssertTrue(editor.replacements.isEmpty)
        XCTAssertTrue(state.correctionHistory.isEmpty)
    }

    @MainActor
    func testCancellationDoesNotPasteAndReleasesGate() async throws {
        let (environment, state, editor, api, service) = try fixture()
        defer { _ = environment }
        let task = Task { await service.performCorrection() }
        await api.waitUntilStarted()
        task.cancel()
        await api.finish()
        await task.value
        XCTAssertTrue(editor.replacements.isEmpty)
        XCTAssertTrue(state.correctionHistory.isEmpty)
        XCTAssertFalse(state.isProcessing)
        XCTAssertTrue(editor.ended)
    }

    @MainActor
    func testNoChangesDoesNotSendEditingCommands() async throws {
        let (environment, state, editor, api, service) = try fixture()
        defer { _ = environment }
        let task = Task { await service.performCorrection() }
        await api.waitUntilStarted()
        await api.finish("teh text")
        await task.value
        XCTAssertTrue(editor.replacements.isEmpty)
        XCTAssertTrue(state.correctionHistory.isEmpty)
    }

    @MainActor
    func testFailureReleasesGateAndPreservesText() async throws {
        let (environment, state, editor, api, service) = try fixture()
        defer { _ = environment }
        let task = Task { await service.performCorrection() }
        await api.waitUntilStarted()
        await api.fail()
        await task.value
        XCTAssertTrue(editor.replacements.isEmpty)
        XCTAssertNotNil(state.lastError)
        XCTAssertFalse(state.isProcessing)
        XCTAssertTrue(editor.ended)
    }
}
