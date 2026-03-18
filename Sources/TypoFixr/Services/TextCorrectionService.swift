import Foundation
import AppKit

class TextCorrectionService {
    private let appState: AppState
    private let groqService = GroqService.shared

    enum SelectionSource: Equatable {
        case existingSelection
        case paragraphFallback
        case lineFallback
    }

    // MARK: - Timing Constants
    private let keyPressDelay: UInt64 = 10_000_000      // 0.01s between key down/up
    private let selectionDelay: UInt64 = 50_000_000     // 0.05s after selection commands
    private let clipboardDelay: UInt64 = 80_000_000     // 0.08s for clipboard operations

    init(appState: AppState) {
        self.appState = appState
    }

    @MainActor
    func performCorrection() async {
        TelemetryService.shared.track(.correctionStarted)

        // Check accessibility permission
        guard appState.hasAccessibilityPermission else {
            appState.lastError = "Accessibility permission required"
            appState.setIconState(.noPermission)
            HUDService.shared.show(title: "Permission Needed", subtitle: "Grant Accessibility access", isSuccess: false)
            TelemetryService.shared.track(.correctionFailed(reason: .accessibilityPermissionMissing))
            return
        }

        // Check network connectivity
        guard NetworkMonitor.shared.isConnected else {
            appState.lastError = "No internet connection"
            appState.setIconState(.offline)
            HUDService.shared.show(title: "No Connection", subtitle: "Check your internet", isSuccess: false)
            TelemetryService.shared.track(.correctionFailed(reason: .offline))
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
    enum SelectionResult: Equatable {
        case success(text: String, source: SelectionSource)
        case tooLong(selected: String)
        case noSelection
    }

    @MainActor
    private func performClipboardCorrection() async {
        let pasteboard = NSPasteboard.general
        let savedClipboard = pasteboard.string(forType: .string)
        let frontmostAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let characterLimit = AppState.characterLimit

        appState.isProcessing = true
        defer { appState.isProcessing = false }
        appState.lastError = nil
        appState.setIconState(.processing)

        let selectionResult = await resolveSelectionResult(
            checkExistingSelection: { [self] in
                await checkExistingSelection(pasteboard: pasteboard, characterLimit: characterLimit)
            },
            tryParagraphSelection: { [self] in
                await tryParagraphSelection(pasteboard: pasteboard, characterLimit: characterLimit)
            },
            tryLineSelection: { [self] in
                await tryLineSelection(pasteboard: pasteboard, characterLimit: characterLimit)
            }
        )

        // Handle the result
        let rawTextToCorrect: String
        let selectionSource: SelectionSource
        switch selectionResult {
        case .success(let text, let source):
            rawTextToCorrect = text
            selectionSource = source

        case .tooLong(let selected):
            appState.setIconState(.error, autoReset: true)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            TelemetryService.shared.track(.correctionFailed(reason: .selectionTooLong))
            await showTextTooLongAlert(characterCount: selected.count)
            return

        case .noSelection:
            appState.setIconState(.error, autoReset: true)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            HUDService.shared.show(title: "Select Text", subtitle: "Highlight text first", isSuccess: false)
            TelemetryService.shared.track(.correctionFailed(reason: .noSelection))
            return
        }

        let textToCorrect = Self.normalizeCapturedTextForCorrection(
            text: rawTextToCorrect,
            appBundleId: frontmostAppBundleId,
            source: selectionSource
        )

        // Verify we have text
        guard !textToCorrect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appState.setIconState(.error, autoReset: true)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            HUDService.shared.show(title: "Select Text", subtitle: "Highlight text first", isSuccess: false)
            TelemetryService.shared.track(
                .correctionFailed(reason: .noSelection, selectionSource: selectionSource)
            )
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
                appState.setIconState(.error, autoReset: true)
                restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                TelemetryService.shared.track(.securityWarningShown(kind: .promptInjection))
                TelemetryService.shared.track(.correctionFailed(reason: .promptInjectionBlocked))
                await showBlockedAlert(patterns: patterns)
                return

            case .sensitiveDataWarning:
                // Allow user choice
                if let warning = SecurityService.shared.getWarningMessage(for: securityResult) {
                    TelemetryService.shared.track(.securityWarningShown(kind: .sensitiveData))
                    let shouldProceed = await showSecurityWarningAlert(title: warning.title, message: warning.message)
                    if !shouldProceed {
                        appState.setIconState(.normal)
                        restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                        TelemetryService.shared.track(
                            .correctionFailed(reason: .sensitiveDataCancelled, selectionSource: selectionSource)
                        )
                        return
                    }
                }
            }
        }

        do {
            // Show loading HUD while API call is in flight
            HUDService.shared.showLoading(title: "Fixing...", subtitle: "Checking your text")

            // Call Groq API
            let result = try await groqService.correctText(
                textToCorrect,
                apiKey: appState.groqApiKey,
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

                appState.setIconState(.success, autoReset: true)
                restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
                HUDService.shared.show(title: "No Changes", subtitle: "Your text looks good!", isSuccess: true)
                TelemetryService.shared.track(.correctionNoChanges(selectionSource: selectionSource))
                return
            }

            await ensureSelectionBeforePaste(
                selectionSource: selectionSource,
                probeSelection: { [self] in hasActiveTextSelection() },
                reSelect: { [self] in
                    switch selectionSource {
                    case .paragraphFallback:
                        await simulateKeyPress(keyCode: 126, modifiers: [.maskAlternate, .maskShift])
                        try? await Task.sleep(nanoseconds: selectionDelay)
                    case .lineFallback:
                        await simulateKeyPress(keyCode: 123, modifiers: [.maskCommand, .maskShift])
                        try? await Task.sleep(nanoseconds: selectionDelay)
                    case .existingSelection:
                        break
                    }
                }
            )

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
                appBundleId: frontmostAppBundleId,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens
            )

            appState.addCorrection(correction)

            // Show success icon and HUD
            appState.setIconState(.success, autoReset: true)
            HUDService.shared.show(title: "Fixed!", subtitle: "⌘Z to undo", isSuccess: true)
            TelemetryService.shared.track(.correctionSucceeded(selectionSource: selectionSource))

        } catch let error as GroqService.APIError {
            appState.lastError = error.localizedDescription
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: error.localizedDescription, isSuccess: false)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            TelemetryService.shared.track(
                .correctionFailed(
                    reason: CorrectionFailureReason(apiError: error),
                    selectionSource: selectionSource
                )
            )
        } catch {
            appState.lastError = error.localizedDescription
            appState.setIconState(.error, autoReset: true)
            HUDService.shared.show(title: "Error", subtitle: "An unexpected error occurred", isSuccess: false)
            restoreClipboard(pasteboard: pasteboard, savedContent: savedClipboard)
            TelemetryService.shared.track(
                .correctionFailed(reason: .unexpected, selectionSource: selectionSource)
            )
        }
    }

    @MainActor
    func resolveSelectionResult(
        checkExistingSelection: () async -> SelectionResult,
        tryParagraphSelection: () async -> SelectionResult,
        tryLineSelection: () async -> SelectionResult
    ) async -> SelectionResult {
        // Step 1: Always check for existing selection first (works in all apps)
        var selectionResult = await checkExistingSelection()

        // Step 2: If no selection, try smart paragraph selection
        if case .noSelection = selectionResult {
            selectionResult = await tryParagraphSelection()
        }

        // Step 3: If still no selection, try line selection as last resort
        if case .noSelection = selectionResult {
            selectionResult = await tryLineSelection()
        }

        return selectionResult
    }

    /// Ensures text is still selected before pasting corrected text.
    /// If the selection was lost (e.g. during API call in some apps), re-selects using the original strategy.
    /// For .existingSelection source, the user made the selection — we trust it persists.
    @MainActor
    func ensureSelectionBeforePaste(
        selectionSource: SelectionSource,
        probeSelection: () -> Bool,
        reSelect: () async -> Void
    ) async {
        // User-made selections are trusted to persist
        guard selectionSource != .existingSelection else { return }

        // Check if selection is still active
        guard !probeSelection() else { return }

        // Selection lost — re-select using the original strategy
        await reSelect()
    }

    // MARK: - AX Selection Check

    /// Lightweight AX check: is there actually selected text in the focused element?
    /// Returns true (conservative) if AX check fails or is unsupported.
    private func hasActiveTextSelection() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return true
        }
        var selectedText: AnyObject?
        let result = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard result == .success else {
            return true
        }
        return !(selectedText as? String ?? "").isEmpty
    }

    // MARK: - Selection Strategies

    /// Check if user already has text selected (Cmd+C to copy)
    private func checkExistingSelection(pasteboard: NSPasteboard, characterLimit: Int) async -> SelectionResult {
        // AX pre-check: if no text is selected, skip Cmd+C to prevent block-copy in Notion
        guard hasActiveTextSelection() else {
            return .noSelection
        }

        pasteboard.clearContents()
        await simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // C key
        try? await Task.sleep(nanoseconds: clipboardDelay)

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return .noSelection
        }

        // Whitespace-only selection (e.g. accidental trailing space) — fall through to paragraph/line selection
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noSelection
        }

        if text.count > characterLimit {
            return .tooLong(selected: text)
        }

        return .success(text: text, source: .existingSelection)
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

        return .success(text: text, source: .paragraphFallback)
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

        return .success(text: text, source: .lineFallback)
    }

    // MARK: - Notes Input Normalization

    /// Normalizes copied text before correction to remove Notes-specific auto-selection artifacts.
    /// Only applies to Apple Notes paragraph/line fallback capture; manual selections are preserved.
    static func normalizeCapturedTextForCorrection(text: String, appBundleId: String?, source: SelectionSource) -> String {
        guard appBundleId == "com.apple.Notes" else { return text }

        switch source {
        case .existingSelection:
            return text
        case .paragraphFallback, .lineFallback:
            break
        }

        // Multi-line text: skip bullet stripping, let GroqService's list-aware path handle it
        if text.contains("\n") {
            return text
        }

        let patterns = [
            #"^\s*[-*•–—]\s*\[(?: |x|X)\]\s+"#,
            #"^\s*\[(?: |x|X)\]\s+"#,
            #"^\s*[-*•–—]\s+"#
        ]

        for pattern in patterns {
            if let updatedText = replacingFirstRegexMatchIfFound(in: text, pattern: pattern, with: "") {
                return updatedText
            }
        }

        return text
    }

    private static func replacingFirstRegexMatchIfFound(in text: String, pattern: String, with replacement: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        return regex.stringByReplacingMatches(in: text, options: [], range: match.range, withTemplate: replacement)
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

    /// Virtual key codes for modifier keys used in flagsChanged events
    private static let modifierKeyCodes: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskShift,     56),  // Left Shift
        (.maskCommand,   55),  // Left Command
        (.maskAlternate, 58),  // Left Option
        (.maskControl,   59),  // Left Control
    ]

    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) async {
        let source = CGEventSource(stateID: .hidSystemState)

        // Send flagsChanged events for modifier key presses (required for Electron/Chromium apps)
        var activeFlags = CGEventFlags()
        if !modifiers.isEmpty {
            for (flag, modKeyCode) in Self.modifierKeyCodes where modifiers.contains(flag) {
                activeFlags.insert(flag)
                if let flagDown = CGEvent(keyboardEventSource: source, virtualKey: modKeyCode, keyDown: true) {
                    flagDown.type = .flagsChanged
                    flagDown.flags = activeFlags
                    flagDown.post(tap: .cghidEventTap)
                }
            }
        }

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

        // Release modifier keys in reverse order
        if !modifiers.isEmpty {
            for (flag, modKeyCode) in Self.modifierKeyCodes.reversed() where modifiers.contains(flag) {
                activeFlags.remove(flag)
                if let flagUp = CGEvent(keyboardEventSource: source, virtualKey: modKeyCode, keyDown: false) {
                    flagUp.type = .flagsChanged
                    flagUp.flags = activeFlags
                    flagUp.post(tap: .cghidEventTap)
                }
            }
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
    @MainActor
    private func showSecurityWarningAlert(title: String, message: String) async -> Bool {
        // Prevent settings window from appearing during alert
        appState.isShowingSecurityAlert = true
        defer { appState.isShowingSecurityAlert = false }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Send Anyway")

        // Make alert float above everything without activating other app windows
        alert.window.level = .floating

        let response = alert.runModal()
        return response == .alertSecondButtonReturn
    }

    /// Shows a blocking alert for prompt injection attempts (no option to proceed)
    @MainActor
    private func showBlockedAlert(patterns: [String]) async {
        appState.isShowingSecurityAlert = true
        defer { appState.isShowingSecurityAlert = false }

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
               let url = URL(string: "mailto:\(AppHelpers.feedbackEmail)?subject=\(encodedSubject)&body=\(encodedBody)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Shows an alert when selected text exceeds the character limit
    @MainActor
    private func showTextTooLongAlert(characterCount: Int) async {
        appState.isShowingSecurityAlert = true
        defer { appState.isShowingSecurityAlert = false }

        let alert = NSAlert()
        alert.messageText = "Text Too Long"
        alert.informativeText = """
            Selected text is \(characterCount) characters, which exceeds the \(AppState.characterLimit) character limit.

            Please highlight a smaller portion of text and try again.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating

        _ = alert.runModal()
    }
}
