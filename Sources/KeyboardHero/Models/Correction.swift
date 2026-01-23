import Foundation

struct Correction: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let originalText: String
    let correctedText: String
    let appBundleId: String?
    var reverted: Bool
    let inputTokens: Int?
    let outputTokens: Int?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        originalText: String,
        correctedText: String,
        appBundleId: String? = nil,
        reverted: Bool = false,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalText = originalText
        self.correctedText = correctedText
        self.appBundleId = appBundleId
        self.reverted = reverted
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
    
    // MARK: - Display Helpers
    var truncatedOriginal: String {
        truncate(originalText, maxLength: 50)
    }
    
    var truncatedCorrected: String {
        truncate(correctedText, maxLength: 50)
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}
