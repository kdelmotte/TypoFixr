import AppKit
import Foundation

@MainActor
struct CorrectionFeedback {
    var message: (String, String, Bool) -> Void
    var loading: () -> Void
    var confirmSensitive: (String, String) async -> Bool
    var blocked: ([String]) -> Void = { _ in }
    var tooLong: (Int) -> Void = { _ in }

    static let live = CorrectionFeedback(
        message: { HUDService.shared.show(title: $0, subtitle: $1, isSuccess: $2) },
        loading: { HUDService.shared.showLoading(title: "Checking text…", subtitle: "Keep your selection in place.") },
        confirmSensitive: { title, message in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Send Anyway")
            alert.window.level = .floating
            return alert.runModal() == .alertSecondButtonReturn
        },
        blocked: { showBlockedAlert(patterns: $0) },
        tooLong: { showTextTooLongAlert(characterCount: $0) }
    )
    /// Shows a blocking alert for prompt injection attempts (no option to proceed)
    private static func showBlockedAlert(patterns: [String]) {
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
            let subject = "\(AppHelpers.productName) False Positive Report"
            let body = "Detected patterns: \(patterns.joined(separator: ", "))\n\nPlease describe what you were trying to correct:"
            if let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "mailto:\(AppHelpers.feedbackEmail)?subject=\(encodedSubject)&body=\(encodedBody)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Shows an alert when selected text exceeds the character limit
    private static func showTextTooLongAlert(characterCount: Int) {
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
