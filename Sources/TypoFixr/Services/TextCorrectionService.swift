import Foundation
import AppKit

@MainActor
final class TextCorrectionService {
    private let appState: AppState
    private let corrector: any TextCorrecting
    private let editor: any CorrectionTextEditing
    private let isConnected: () -> Bool
    private let feedback: CorrectionFeedback

    enum SelectionSource: Equatable {
        case existingSelection
        case paragraphFallback
        case lineFallback
    }

    init(appState: AppState,
         corrector: any TextCorrecting = GroqService.shared,
         editor: (any CorrectionTextEditing)? = nil,
         isConnected: @escaping () -> Bool = { NetworkMonitor.shared.isConnected },
         feedback: CorrectionFeedback? = nil) {
        self.appState = appState
        self.corrector = corrector
        self.editor = editor ?? ClipboardTextEditor()
        self.isConnected = isConnected
        self.feedback = feedback ?? .live
    }

    func performCorrection() async {
        // Acquire the gate synchronously, before any suspension, including capture.
        guard !appState.isProcessing else { return }
        appState.isProcessing = true
        defer {
            editor.endSession()
            appState.isProcessing = false
        }
        appState.lastError = nil
        TelemetryService.shared.track(.correctionStarted)

        guard appState.hasAccessibilityPermission else {
            fail("Accessibility permission required", state: .noPermission, reason: .accessibilityPermissionMissing)
            return
        }
        guard isConnected() else {
            fail("No internet connection", state: .offline, reason: .offline)
            return
        }
        guard !appState.groqApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(GroqService.APIError.noApiKey.localizedDescription, reason: .noApiKey)
            return
        }

        appState.setIconState(.processing)
        var selectionSource: SelectionSource?
        do {
            try Task.checkCancellation()
            let selection = try await editor.captureSelection(characterLimit: AppState.characterLimit)
            selectionSource = selection.source
            // Keep raw clipboard text for destination verification; normalize only known capture artifacts.
            let text = selection.correctionText
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TextEditingError.noSelection
            }

            if appState.securityWarningsEnabled {
                let security = SecurityService.shared.checkText(text)
                switch security {
                case .safe: break
                case .promptInjectionWarning(let patterns):
                    TelemetryService.shared.track(.securityWarningShown(kind: .promptInjection))
                    fail("The selection contains instructions that could manipulate the AI.", reason: .promptInjectionBlocked)
                    showAlert { feedback.blocked(patterns) }
                    return
                case .sensitiveDataWarning:
                    if let warning = SecurityService.shared.getWarningMessage(for: security) {
                        TelemetryService.shared.track(.securityWarningShown(kind: .sensitiveData))
                        appState.isShowingSecurityAlert = true
                        let proceed = await feedback.confirmSensitive(warning.title, warning.message)
                        appState.isShowingSecurityAlert = false
                        guard proceed else {
                            appState.setIconState(.normal)
                            TelemetryService.shared.track(.correctionFailed(reason: .sensitiveDataCancelled, selectionSource: selection.source))
                            return
                        }
                    }
                }
            }

            try Task.checkCancellation()
            guard editor.isSelectionCurrent(selection) else { throw TextEditingError.destinationChanged }
            feedback.loading()
            let result = try await corrector.correctText(text,
                apiKey: appState.groqApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                languagePreference: appState.languagePreference)
            try Task.checkCancellation()
            guard editor.isSelectionCurrent(selection) else { throw TextEditingError.destinationChanged }

            let corrected = Self.preservingBoundaryWhitespace(original: text, corrected: result.correctedText)
            if Self.textIsUnchanged(original: text, corrected: corrected) {
                // No synthetic arrow key: it can move a cursor the user has moved.
                appState.setIconState(.success, autoReset: true)
                feedback.message("No Changes", "Your text looks good!", true)
                TelemetryService.shared.track(.correctionNoChanges(selectionSource: selection.source))
                return
            }

            // Copy-verify the selection again immediately before pasting.
            try await editor.replaceSelection(selection, with: corrected)
            appState.addCorrection(Correction(originalText: text, correctedText: corrected,
                appBundleId: selection.appBundleID, inputTokens: result.inputTokens, outputTokens: result.outputTokens))
            appState.setIconState(.success, autoReset: true)
            feedback.message("Fixed!", "⌘Z to undo", true)
            TelemetryService.shared.track(.correctionSucceeded(selectionSource: selection.source))
        } catch is CancellationError {
            appState.setIconState(.normal)
            TelemetryService.shared.track(.correctionFailed(reason: .cancelled, selectionSource: selectionSource))
        } catch let error as TextEditingError {
            let reason: CorrectionFailureReason
            switch error {
            case .noSelection: reason = .noSelection
            case .tooLong(let count):
                reason = .selectionTooLong
                showAlert { feedback.tooLong(count) }
            case .destinationChanged: reason = .destinationChanged
            case .clipboardUnavailable: reason = .clipboardUnavailable
            case .eventUnavailable: reason = .unexpected
            }
            fail(error.localizedDescription, reason: reason, source: selectionSource)
        } catch let error as GroqService.APIError {
            fail(error.localizedDescription, reason: CorrectionFailureReason(apiError: error), source: selectionSource)
        } catch {
            fail(error.localizedDescription, reason: .unexpected, source: selectionSource)
        }
    }

    private func showAlert(_ action: () -> Void) {
        appState.isShowingSecurityAlert = true
        defer { appState.isShowingSecurityAlert = false }
        action()
    }

    private func fail(_ message: String, state: MenuBarIconState = .error,
                      reason: CorrectionFailureReason, source: SelectionSource? = nil) {
        appState.lastError = message
        appState.setIconState(state, autoReset: state == .error)
        feedback.message("Correction Stopped", message, false)
        TelemetryService.shared.track(.correctionFailed(reason: reason, selectionSource: source))
    }

    nonisolated static func preservingBoundaryWhitespace(original: String, corrected: String) -> String {
        let leading = String(original.prefix(while: { $0.isWhitespace }))
        let trailing = String(original.reversed().prefix(while: { $0.isWhitespace }).reversed())
        return leading + corrected.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
    }

    nonisolated static func textIsUnchanged(original: String, corrected: String) -> Bool {
        original.trimmingCharacters(in: .whitespacesAndNewlines) == corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
