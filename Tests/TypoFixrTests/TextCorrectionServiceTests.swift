import XCTest
@testable import TypoFixr

private actor CapturingCorrector: TextCorrecting {
    private(set) var input: String?
    func correctText(_ text: String, apiKey: String, languagePreference: String) async throws -> GroqService.CorrectionResult {
        input = text
        return .init(correctedText: text.replacingOccurrences(of: "teh", with: "the"), inputTokens: 1, outputTokens: 1)
    }
}

@MainActor
private final class PreservationEditor: CorrectionTextEditing {
    let selection: CapturedSelection
    var pasted: String?
    init(_ text: String, source: TextCorrectionService.SelectionSource) {
        selection = CapturedSelection(text: text, source: source, appBundleID: "com.apple.Notes")
    }
    func captureSelection(characterLimit: Int) async throws -> CapturedSelection { selection }
    func isSelectionCurrent(_ selection: CapturedSelection) -> Bool { true }
    func replaceSelection(_ selection: CapturedSelection, with text: String) async throws { pasted = text }
    func endSession() {}
}

final class TextCorrectionServicePreservationTests: XCTestCase {
    @MainActor
    func testActualSelectedListMarkersArePreservedForEverySelectionStrategy() async throws {
        for source in [TextCorrectionService.SelectionSource.existingSelection, .paragraphFallback, .lineFallback] {
            for text in ["- teh text", "[ ] teh text", "- [ ] teh text", "  - teh text\n", "<teh>", "teh 👩‍💻"] {
                let environment = try TestEnvironment()
                let state = environment.makeAppState()
                state.hasAccessibilityPermission = true
                state.groqApiKey = "test-key"
                state.securityWarningsEnabled = false
                let api = CapturingCorrector()
                let editor = PreservationEditor(text, source: source)
                let service = TextCorrectionService(appState: state, corrector: api, editor: editor, isConnected: { true },
                    feedback: .init(message: { _, _, _ in }, loading: {}, confirmSensitive: { _, _ in false }))
                await service.performCorrection()
                let input = await api.input
                XCTAssertEqual(input, text)
                XCTAssertEqual(editor.pasted, text.replacingOccurrences(of: "teh", with: "the"))
            }
        }
    }
}
