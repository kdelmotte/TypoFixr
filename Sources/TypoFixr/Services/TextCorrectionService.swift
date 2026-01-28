import Foundation
import AppKit

class TextCorrectionService {
    private let appState: AppState
    private let openAIService = OpenAIService.shared

    // MARK: - Timing Constants
    private let keyPressDelay: UInt64 = 10_000_000      // 0.01s between key down/up
    private let selectionDelay: UInt64 = 50_000_000     // 0.05s after selection commands
    private let clipboardDelay: UInt64 = 80_000_000     // 0.08s for clipboard operations

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

        // Check network connectivity
        guard NetworkMonitor.shared.isConnected else {
            appState.lastError = "No internet connection"
            appState.setIconState(.offline)
            HUDService.shared.show(title: "No Connection", subtitle: "Check your internet", isSuccess: false)
            return
        }

        // Show processing state
        appState.setIconState(.processing)

        // Use clipboard-based correction - it's reliable across all apps
        await performClipboardCorrection()
    }

    // MARK: - Clipboard-based Correction
    // Uses clipboard (Cmd+C/Cmd+V) for reliability across all apps.
    // Direct Accessibility API text manipulation is unreliable in many apps.

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
            try? await Task.sleep(nanoseconds: selectionDelay)

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

        // Security check if enabled
        if appState.securityWarningsEnabled {
            let securityResult = SecurityService.shared.checkText(textToCorrect)

            switch securityResult {
            case .safe:
                break // Continue with correction

            case .promptInjectionWarning(let patterns):
                // Block completely - no option to proceed
                appState.isProcessing = false
                appState.setIconState(.error, autoReset: true)
                restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                await showBlockedAlert(patterns: patterns)
                return

            case .sensitiveDataWarning:
                // Allow user choice
                if let warning = SecurityService.shared.getWarningMessage(for: securityResult) {
                    let shouldProceed = await showSecurityWarningAlert(title: warning.title, message: warning.message)
                    if !shouldProceed {
                        appState.isProcessing = false
                        appState.setIconState(.normal)
                        restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                        return
                    }
                }

            case .blocked:
                // Reserved for future hard blocks
                appState.isProcessing = false
                appState.setIconState(.error, autoReset: true)
                restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                return
            }
        }

        do {
            // Call OpenAI
            let result = try await openAIService.correctText(
                textToCorrect,
                apiKey: appState.openAIApiKey,
                languagePreference: appState.languagePreference
            )

            // Extract whitespace boundaries from original text to preserve paragraph spacing
            let (leadingWhitespace, trailingWhitespace) = extractWhitespaceBoundaries(textToCorrect)

            // Apply original whitespace to corrected text
            // Strip formatting artifacts (like ">") that Notes.app includes before adding trailing whitespace
            let correctedWithWhitespace = leadingWhitespace
                + stripTrailingFormattingArtifacts(result.correctedText.trimmingCharacters(in: .whitespacesAndNewlines))
                + trailingWhitespace

            // Check if text actually changed (ignore insignificant whitespace differences)
            let originalNormalized = textToCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
            let correctedNormalized = correctedWithWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)

            if correctedNormalized == originalNormalized {
                // Deselect text by pressing right arrow (moves cursor to end of selection)
                await simulateKeyPress(keyCode: 124, modifiers: []) // Right arrow

                appState.isProcessing = false
                appState.setIconState(.success, autoReset: true)
                restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                HUDService.shared.show(title: "No Changes", subtitle: "Your text looks good!", isSuccess: true)
                return
            }

            // Put corrected text in clipboard and paste
            pasteboard.clearContents()
            pasteboard.setString(correctedWithWhitespace, forType: .string)

            // Paste with Cmd+V
            await simulateKeyPress(keyCode: 9, modifiers: .maskCommand) // V key

            // Small delay to let paste complete
            try? await Task.sleep(nanoseconds: clipboardDelay)

            // Restore original clipboard
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)

            // Create correction record
            let correction = Correction(
                originalText: textToCorrect,
                correctedText: correctedWithWhitespace,
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
        try? await Task.sleep(nanoseconds: clipboardDelay)

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
        try? await Task.sleep(nanoseconds: selectionDelay)

        // Copy selected text
        pasteboard.clearContents()
        await simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // C key
        try? await Task.sleep(nanoseconds: clipboardDelay)

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
        try? await Task.sleep(nanoseconds: selectionDelay)

        // Copy selected text
        pasteboard.clearContents()
        await simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // C key
        try? await Task.sleep(nanoseconds: clipboardDelay)

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return .noSelection
        }

        if text.count > characterLimit {
            return .tooLong(selected: text)
        }

        return .success(text)
    }

    /// Extracts leading and trailing whitespace from text
    private func extractWhitespaceBoundaries(_ text: String) -> (leading: String, trailing: String) {
        let leading = String(text.prefix(while: { $0.isWhitespace }))
        let trailing = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
        return (leading, trailing)
    }

    /// Strips trailing formatting artifacts that apps like Notes.app include when copying
    /// These are markers like ">" (blockquote) that aren't user content
    /// Only strips ">" since it's the known Notes.app artifact; other markers like "-", "*"
    /// could be intentional punctuation (e.g., "see above -" or "important *")
    private func stripTrailingFormattingArtifacts(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)

        // Strip trailing ">" - Notes.app blockquote artifact
        // This is safe because sentences almost never legitimately end with ">"
        while result.hasSuffix(">") {
            result = String(result.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        return result
    }

    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) async {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }

        // Small delay between down and up
        try? await Task.sleep(nanoseconds: keyPressDelay)

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

    /// Shows security warning alert and returns true if user wants to proceed
    private func showSecurityWarningAlert(title: String, message: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                // Prevent settings window from appearing during alert
                self?.appState.isShowingSecurityAlert = true

                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Send Anyway")

                // Make alert float above everything without activating other app windows
                alert.window.level = .floating

                let response = alert.runModal()

                self?.appState.isShowingSecurityAlert = false
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }

    /// Shows a blocking alert for prompt injection attempts (no option to proceed)
    private func showBlockedAlert(patterns: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { [weak self] in
                self?.appState.isShowingSecurityAlert = true

                let alert = NSAlert()
                alert.messageText = "Request Blocked"

                let patternList = patterns.prefix(3).map { "• \($0)" }.joined(separator: "\n")
                alert.informativeText = """
                    Your text contains patterns that could manipulate the AI:

                    \(patternList)

                    This request will not be processed.

                    Not expected? Let us know!
                    """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Send Feedback")
                alert.window.level = .floating

                let response = alert.runModal()

                // If user clicked "Send Feedback", open mail client
                if response == .alertSecondButtonReturn {
                    let subject = "TypoFixr False Positive Report"
                    let body = "Detected patterns: \(patterns.joined(separator: ", "))\n\nPlease describe what you were trying to correct:"
                    if let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let url = URL(string: "mailto:feedback@typofixr.com?subject=\(encodedSubject)&body=\(encodedBody)") {
                        NSWorkspace.shared.open(url)
                    }
                }

                self?.appState.isShowingSecurityAlert = false
                continuation.resume()
            }
        }
    }
}
