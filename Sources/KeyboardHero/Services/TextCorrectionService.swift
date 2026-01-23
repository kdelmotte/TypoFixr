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
            showNotification(title: "Permission Required", message: "Please grant Accessibility permission in System Preferences.")
            return
        }
        
        // Get current text field
        guard let textFieldInfo = accessibilityService.getCurrentTextField() else {
            appState.lastError = "No text field focused"
            showNotification(title: "No Text Field", message: "Please focus on a text input field.")
            return
        }
        
        // Check if editable
        guard textFieldInfo.isEditable else {
            appState.lastError = "Text field is read-only"
            showNotification(title: "Read-Only", message: "This text field is read-only.")
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
            showNotification(title: "Error", message: "Could not capture text from the field.")
            return
        }
        
        // Handle too long text
        if capturedText.strategy == .tooLong {
            appState.lastError = "Text too long"
            showNotification(
                title: "Text Too Long",
                message: "Please select the specific text you want to fix (limit: \(appState.characterLimit) characters)."
            )
            return
        }
        
        // Handle empty text
        if capturedText.isEmpty {
            showNotification(title: "No Text", message: "No text to fix.")
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
            
            // Check if text actually changed
            if result.correctedText == capturedText.text {
                appState.isProcessing = false
                showNotification(title: "No Changes", message: "Your text looks good!")
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
                showNotification(title: "Error", message: "Could not replace the text. Try selecting the text first.")
                
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
            showNotification(title: "Error", message: error.localizedDescription ?? "An error occurred")
            
            // Log failed attempt
            DatabaseManager.shared.logUsage(
                inputTokenCount: nil,
                outputTokenCount: nil,
                app: textFieldInfo.appBundleId,
                wasSuccessful: false
            )
        } catch {
            appState.lastError = error.localizedDescription
            showNotification(title: "Error", message: "An unexpected error occurred.")
            
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
            
            showNotification(title: "Reverted", message: "Text restored to original.")
        } else {
            showNotification(title: "Error", message: "Could not revert. Try using Cmd+Z.")
        }
    }
    
    func revertFromHistory(_ correction: Correction) async {
        // This requires the text field to still be focused on the same content
        // For simplicity, we'll just notify the user
        // In a production app, we'd need to track more state
        
        await MainActor.run {
            appState.revertCorrection(correction)
            showNotification(
                title: "Marked as Reverted",
                message: "Use Cmd+Z in the app to undo, or copy the original text from history."
            )
        }
    }
    
    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = nil
        
        NSUserNotificationCenter.default.deliver(notification)
        
        // Also show as a brief alert if the notification center is disabled
        // This uses the deprecated API but it's simple and works
    }
}
