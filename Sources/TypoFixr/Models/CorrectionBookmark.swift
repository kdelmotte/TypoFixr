import Foundation

/// Tracks where the last correction ended in a specific text field,
/// allowing subsequent corrections to only process new text.
struct CorrectionBookmark {
    /// The bundle ID of the app containing the text field
    let appBundleId: String
    
    /// A signature identifying the specific text field (based on position, role, etc.)
    let textFieldSignature: String
    
    /// The character index where the last correction ended
    let endIndex: Int
    
    /// When this bookmark was created
    let timestamp: Date
    
    /// The corrected text at the bookmark position (for validation)
    let textAtBookmark: String
    
    init(
        appBundleId: String,
        textFieldSignature: String,
        endIndex: Int,
        textAtBookmark: String
    ) {
        self.appBundleId = appBundleId
        self.textFieldSignature = textFieldSignature
        self.endIndex = endIndex
        self.timestamp = Date()
        self.textAtBookmark = textAtBookmark
    }
    
    /// Check if this bookmark is still valid (not too old)
    var isValid: Bool {
        // Bookmarks expire after 30 minutes
        let expirationInterval: TimeInterval = 30 * 60
        return Date().timeIntervalSince(timestamp) < expirationInterval
    }
    
    /// Generate a unique key for storing this bookmark
    static func generateKey(appBundleId: String, textFieldSignature: String) -> String {
        return "\(appBundleId):\(textFieldSignature)"
    }
}
