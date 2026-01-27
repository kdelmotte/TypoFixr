import Foundation
import AppKit

class TextCorrectionService {
    private let appState: AppState
    private let openAIService = OpenAIService.shared

    init(appState: AppState) {
        self.appState = appState
    }

    @MainActor
    func performCorrection() async {
        // Check accessibility permission
        guard appState.hasAccessibilityPermission else {
            appState.lastError = "Accessibility permission required"
            appState.setIconState(.noPermission)
            HUDService.shared.show(title: "Permission Needed", subtitle: "Grant Accessibility access", isSuccess: false)
            return
        }

        // Show processing state
        appState.setIconState(.processing)

        // Use clipboard-based correction - it's reliable across all apps
        await performClipboardCorrection()
    }

    // MARK: - Clipboard-based Correction

    /// Result of smart text selection
    private enum SelectionResult {
        case success(String)
        case tooLong(selected: String)
        case noSelection
    }

    @MainActor
    private func performClipboardCorrection() async {
        let pasteboard = NSPasteboard.general
        let savedClipboard = pasteboard.string(forType: .string)
        let characterLimit = appState.characterLimit

        appState.isProcessing = true
        appState.lastError = nil
        appState.setIconState(.processing)

        // Step 1: Always check for existing selection first (works in all apps)
        var selectionResult = await checkExistingSelection(pasteboard: pasteboard, characterLimit: characterLimit)

        // Step 2: If no selection, try smart paragraph selection
        if case .noSelection = selectionResult {
            selectionResult = await tryParagraphSelection(pasteboard: pasteboard, characterLimit: characterLimit)
        }

        // Step 3: If paragraph too long, try line selection instead
        if case .tooLong = selectionResult {
            // Deselect first - press right arrow to collapse selection back to cursor position
            await simulateKeyPress(keyCode: 124, modifiers: []) // Right arrow
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            selectionResult = await tryLineSelection(pasteboard: pasteboard, characterLimit: characterLimit)
        }

        // Step 4: If still no selection, try line selection as last resort
        if case .noSelection = selectionResult {
            selectionResult = await tryLineSelection(pasteboard: pasteboard, characterLimit: characterLimit)
        }

        // Handle the result
        let textToCorrect: String
        switch selectionResult {
        case .success(let text):
            textToCorrect = text

        case .tooLong(let selected):
            appState.isProcessing = false
            appState.setIconState(.error, autoReset: true)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            HUDService.shared.show(title: "Text Too Long", subtitle: "Selected \(selected.count) chars (max \(characterLimit))", isSuccess: false)
            return

        case .noSelection:
            appState.isProcessing = false
            appState.setIconState(.error, autoReset: true)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            HUDService.shared.show(title: "Select Text", subtitle: "Highlight text first", isSuccess: false)
            return
        }

        // Verify we have text
        guard !textToCorrect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appState.isProcessing = false
            appState.setIconState(.error, autoReset: true)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            HUDService.shared.show(title: "Select Text", subtitle: "Highlight text first", isSuccess: false)
            return
        }

        do {
            // Call OpenAI
            let result = try await openAIService.correctText(
                textToCorrect,
                apiKey: appState.openAIApiKey,
                languagePreference: appState.languagePreference
            )

            // Check if text actually changed (ignore insignificant whitespace differences)
            let originalNormalized = textToCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
            let correctedNormalized = result.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if correctedNormalized == originalNormalized {
                appState.isProcessing = false
                appState.setIconState(.success, autoReset: true)
                restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                HUDService.shared.show(title: "No Changes", subtitle: "Your text looks good!", isSuccess: true)
                return
            }

            // Put corrected text in clipboard and paste
            pasteboard.clearContents()
            pasteboard.setString(result.correctedText, forType: .string)

            // Paste with Cmd+V
            await simulateKeyPress(keyCode: 9, modifiers: .maskCommand) // V key

            // Small delay to let paste complete
            try? await Task.sleep(nanoseconds: 80_000_000) // 0.08 seconds

            // Restore original clipboard
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)

            // Create correction record
            let correction = Correction(
                originalText: textToCorrect,
                correctedText: result.correctedText,
                appBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens
            )

            appState.addCorrection(correction)

            // Show success icon and HUD
            appState.setIconState(.success, autoReset: true)
            HUDService.shared.show(title: "Fixed!", subtitle: "⌘Z to undo", isSuccess: true)

        } catch let error as OpenAIService.OpenAIError {
            appState.lastError = error.localizedDescription
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: error.localizedDescription, isSuccess: false)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
        } catch {
            appState.lastError = error.localizedDescription
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: "An unexpected error occurred", isSuccess: false)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
        }

        appState.isProcessing = false
    }

    // MARK: - Selection Strategies

    /// Check if user already has text selected (Cmd+C to copy)
    private func checkExistingSelection(pasteboard: NSPasteboard, characterLimit: Int) async -> SelectionResult {
        pasteboard.clearContents()
        await simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // C key
        try? await Task.sleep(nanoseconds: 80_000_000) // 0.08 seconds

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return .noSelection
        }

        if text.count > characterLimit {
            return .tooLong(selected: text)
        }

        return .success(text)
    }

    /// Try to select text BEFORE cursor to start of paragraph (Shift+Option+Up)
    private func tryParagraphSelection(pasteboard: NSPasteboard, characterLimit: Int) async -> SelectionResult {
        // Select backward from cursor to start of paragraph
        await simulateKeyPress(keyCode: 126, modifiers: [.maskAlternate, .maskShift]) // Up arrow
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // Copy selected text
        pasteboard.clearContents()
        await simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // C key
        try? await Task.sleep(nanoseconds: 80_000_000) // 0.08 seconds

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return .noSelection
        }

        if text.count > characterLimit {
            return .tooLong(selected: text)
        }

        return .success(text)
    }

    /// Try to select text BEFORE cursor to start of line (Shift+Cmd+Left)
    private func tryLineSelection(pasteboard: NSPasteboard, characterLimit: Int) async -> SelectionResult {
        // Select backward from cursor to start of line
        await simulateKeyPress(keyCode: 123, modifiers: [.maskCommand, .maskShift]) // Left arrow
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // Copy selected text
        pasteboard.clearContents()
        await simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // C key
        try? await Task.sleep(nanoseconds: 80_000_000) // 0.08 seconds

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return .noSelection
        }

        if text.count > characterLimit {
            return .tooLong(selected: text)
        }

        return .success(text)
    }

    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) async {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }

        // Small delay between down and up
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = modifiers
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func restoreClipboard(pasteboard: NSPasteboard, savedContent: String?) {
        // Delay before restoring to make sure paste completed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            if let saved = savedContent {
                pasteboard.setString(saved, forType: .string)
            }
        }
    }
}
