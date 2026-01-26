import Foundation
import AppKit

class TextCorrectionService {
    private let appState: AppState
    private let accessibilityService = AccessibilityService.shared
    private let openAIService = OpenAIService.shared
    
    // For revert functionality
    private var lastCorrectionInfo: LastCorrectionInfo?
    
    struct LastCorrectionInfo {
        let element: AXUIElement
        let originalText: String
        let correctedText: String
        let startIndex: Int
        let strategy: CaptureStrategy
        let timestamp: Date
    }
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    @MainActor
    func performCorrection() async {
        // Check if we should revert instead
        if appState.canToggleRevert, let lastInfo = lastCorrectionInfo {
            await performRevert(lastInfo)
            return
        }

        // Check accessibility permission
        guard appState.hasAccessibilityPermission else {
            appState.lastError = "Accessibility permission required"
            appState.setIconState(.noPermission)
            HUDService.shared.show(title: "Permission Needed", subtitle: "Grant Accessibility access", isSuccess: false)
            return
        }

        // Show processing state
        appState.setIconState(.processing)

        // Get current text field - if this fails, try clipboard fallback
        guard let textFieldInfo = accessibilityService.getCurrentTextField() else {
            // Fallback to clipboard-based correction for apps like Chrome, Electron apps
            await performClipboardCorrection()
            return
        }

        // Check if editable - if not, try clipboard fallback
        guard textFieldInfo.isEditable else {
            await performClipboardCorrection()
            return
        }
        
        // Get bookmark for this field if exists
        let bookmarkKey = CorrectionBookmark.generateKey(
            appBundleId: textFieldInfo.appBundleId ?? "unknown",
            textFieldSignature: textFieldInfo.fieldSignature
        )
        let bookmark = appState.getBookmark(for: bookmarkKey)
        
        // Capture text using hybrid strategy
        guard let capturedText = accessibilityService.captureTextForCorrection(
            textFieldInfo: textFieldInfo,
            bookmark: bookmark,
            characterLimit: appState.characterLimit
        ) else {
            appState.lastError = "Could not capture text"
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: "Could not capture text", isSuccess: false)
            return
        }
        
        // Handle too long text
        if capturedText.strategy == .tooLong {
            appState.lastError = "Text too long"
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Text Too Long", subtitle: "Select up to \(appState.characterLimit) characters", isSuccess: false)
            return
        }

        // Handle empty text
        if capturedText.isEmpty {
            appState.setIconState(.success, autoReset: true)
            HUDService.shared.show(title: "No Text", subtitle: "No text to fix", isSuccess: true)
            return
        }
        
        // Start processing
        appState.isProcessing = true
        appState.lastError = nil
        
        do {
            // Call OpenAI
            let result = try await openAIService.correctText(
                capturedText.text,
                apiKey: appState.openAIApiKey,
                languagePreference: appState.languagePreference
            )
            
            // Check if text actually changed (ignore insignificant whitespace differences)
            let originalNormalized = capturedText.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let correctedNormalized = result.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if correctedNormalized == originalNormalized {
                appState.isProcessing = false
                appState.setIconState(.success, autoReset: true)
                HUDService.shared.show(title: "No Changes", subtitle: "Your text looks good!", isSuccess: true)
                return
            }
            
            // Replace text
            let success = accessibilityService.replaceText(
                in: textFieldInfo.element,
                originalText: capturedText.text,
                newText: result.correctedText,
                startIndex: capturedText.startIndex,
                strategy: capturedText.strategy
            )
            
            if success {
                // Store correction info for revert
                lastCorrectionInfo = LastCorrectionInfo(
                    element: textFieldInfo.element,
                    originalText: capturedText.text,
                    correctedText: result.correctedText,
                    startIndex: capturedText.startIndex,
                    strategy: capturedText.strategy,
                    timestamp: Date()
                )

                // Create correction record
                let correction = Correction(
                    originalText: capturedText.text,
                    correctedText: result.correctedText,
                    appBundleId: textFieldInfo.appBundleId,
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens
                )

                // Update state
                appState.addCorrection(correction)

                // Show success icon and HUD
                appState.setIconState(.success, autoReset: true)
                HUDService.shared.show(title: "Fixed!", subtitle: "⌘Z to undo", isSuccess: true)

                // Update bookmark
                let newEndIndex = capturedText.startIndex + result.correctedText.count
                let newBookmark = CorrectionBookmark(
                    appBundleId: textFieldInfo.appBundleId ?? "unknown",
                    textFieldSignature: textFieldInfo.fieldSignature,
                    endIndex: newEndIndex,
                    textAtBookmark: String(result.correctedText.suffix(20))
                )
                appState.setBookmark(for: bookmarkKey, bookmark: newBookmark)
                
            } else {
                appState.lastError = "Could not replace text"
                appState.setIconState(.error, autoReset: true)
                HUDService.shared.show(title: "Error", subtitle: "Could not replace text", isSuccess: false)

                // Log failed attempt
                DatabaseManager.shared.logUsage(
                    inputTokenCount: result.inputTokens,
                    outputTokenCount: result.outputTokens,
                    app: textFieldInfo.appBundleId,
                    wasSuccessful: false
                )
            }

        } catch let error as OpenAIService.OpenAIError {
            appState.lastError = error.localizedDescription
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: error.localizedDescription ?? "An error occurred", isSuccess: false)

            // Log failed attempt
            DatabaseManager.shared.logUsage(
                inputTokenCount: nil,
                outputTokenCount: nil,
                app: textFieldInfo.appBundleId,
                wasSuccessful: false
            )
        } catch {
            appState.lastError = error.localizedDescription
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: "An unexpected error occurred", isSuccess: false)

            DatabaseManager.shared.logUsage(
                inputTokenCount: nil,
                outputTokenCount: nil,
                app: textFieldInfo.appBundleId,
                wasSuccessful: false
            )
        }

        appState.isProcessing = false
    }
    
    @MainActor
    private func performRevert(_ lastInfo: LastCorrectionInfo) async {
        // Replace corrected text with original
        let success = accessibilityService.replaceText(
            in: lastInfo.element,
            originalText: lastInfo.correctedText,
            newText: lastInfo.originalText,
            startIndex: lastInfo.startIndex,
            strategy: lastInfo.strategy
        )

        if success {
            // Mark last correction as reverted
            if let lastCorrection = appState.correctionHistory.first {
                appState.revertCorrection(lastCorrection)
            }

            // Clear revert state
            lastCorrectionInfo = nil
            appState.canToggleRevert = false

            appState.setIconState(.success, autoReset: true)
            HUDService.shared.show(title: "Reverted", subtitle: "Original text restored", isSuccess: true)
        } else {
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: "Could not revert. Try ⌘Z", isSuccess: false)
        }
    }

    // MARK: - Clipboard-based Fallback for Chrome, Electron apps, etc.

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
