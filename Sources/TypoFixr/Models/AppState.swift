import Foundation
import SwiftUI
import Combine

// MARK: - Menu Bar Icon State
enum MenuBarIconState {
    case normal
    case processing
    case success
    case error
    case noPermission
    case rateLimited
    case offline
}

class AppState: ObservableObject {
    // MARK: - Permission State
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    // MARK: - Processing State
    @Published var isProcessing: Bool = false
    @Published var shouldTriggerCorrection: Bool = false
    @Published var lastError: String? = nil
    @Published var iconState: MenuBarIconState = .normal
    @Published var isShowingSecurityAlert: Bool = false
    private var iconResetTimer: Timer?
    
    // MARK: - Correction History
    @Published var correctionHistory: [Correction] = []

    // MARK: - Correction Bookmarks
    var correctionBookmarks: [String: CorrectionBookmark] = [:]
    
    // MARK: - Settings
    @Published var keyboardShortcut: KeyboardShortcutConfig {
        didSet {
            saveShortcut()
        }
    }
    @Published var characterLimit: Int {
        didSet {
            UserDefaults.standard.set(characterLimit, forKey: "characterLimit")
        }
    }
    @Published var languagePreference: String {
        didSet {
            UserDefaults.standard.set(languagePreference, forKey: "languagePreference")
        }
    }
    
    // MARK: - Security & Privacy Settings
    @Published var securityWarningsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(securityWarningsEnabled, forKey: "securityWarningsEnabled")
        }
    }
    // MARK: - Rate Limiting
    @Published var correctionsPerMinuteLimit: Int {
        didSet {
            UserDefaults.standard.set(correctionsPerMinuteLimit, forKey: "correctionsPerMinuteLimit")
        }
    }
    @Published var correctionsPerHourLimit: Int {
        didSet {
            UserDefaults.standard.set(correctionsPerHourLimit, forKey: "correctionsPerHourLimit")
        }
    }
    private var recentCorrectionTimestamps: [Date] = []
    
    // MARK: - Spending Cap
    @Published var monthlyTokenLimit: Int {
        didSet {
            UserDefaults.standard.set(monthlyTokenLimit, forKey: "monthlyTokenLimit")
        }
    }
    @Published var spendingCapEnabled: Bool {
        didSet {
            UserDefaults.standard.set(spendingCapEnabled, forKey: "spendingCapEnabled")
        }
    }
    
    // MARK: - API Configuration
    @Published var openAIApiKey: String {
        didSet {
            saveApiKey()
        }
    }
    
    // MARK: - Database
    let databaseManager = DatabaseManager.shared
    
    // MARK: - Initialization
    init() {
        // Load persisted values
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.characterLimit = UserDefaults.standard.object(forKey: "characterLimit") as? Int ?? 1000
        self.languagePreference = UserDefaults.standard.string(forKey: "languagePreference") ?? "auto"
        
        // Load security & privacy settings
        self.securityWarningsEnabled = UserDefaults.standard.object(forKey: "securityWarningsEnabled") as? Bool ?? true

        // Load rate limiting settings
        self.correctionsPerMinuteLimit = UserDefaults.standard.object(forKey: "correctionsPerMinuteLimit") as? Int ?? 15
        self.correctionsPerHourLimit = UserDefaults.standard.object(forKey: "correctionsPerHourLimit") as? Int ?? 100
        
        // Load spending cap settings
        self.monthlyTokenLimit = UserDefaults.standard.object(forKey: "monthlyTokenLimit") as? Int ?? 100000
        self.spendingCapEnabled = UserDefaults.standard.object(forKey: "spendingCapEnabled") as? Bool ?? false
        
        // Load shortcut
        if let data = UserDefaults.standard.data(forKey: "keyboardShortcut"),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcutConfig.self, from: data) {
            self.keyboardShortcut = shortcut
        } else {
            // Default: Cmd + Shift + D
            self.keyboardShortcut = KeyboardShortcutConfig(
                keyCode: 2, // D key
                modifiers: [.command, .shift]
            )
        }
        
        // Load API key from Keychain
        self.openAIApiKey = KeychainHelper.load(key: "openai_api_key") ?? ""
        
        // Load recent history from database
        loadRecentHistory()
    }
    
    // MARK: - History Management
    func addCorrection(_ correction: Correction) {
        // Track for rate limiting
        recentCorrectionTimestamps.append(Date())
        cleanupOldTimestamps()

        correctionHistory.insert(correction, at: 0)
        // Keep only last 10 in memory
        if correctionHistory.count > 10 {
            correctionHistory = Array(correctionHistory.prefix(10))
        }
        // Save to database
        databaseManager.saveCorrection(correction)
    }

    func revertCorrection(_ correction: Correction) {
        if let index = correctionHistory.firstIndex(where: { $0.id == correction.id }) {
            correctionHistory[index].reverted = true
            databaseManager.markCorrectionReverted(correction.id)
        }
    }

    private func loadRecentHistory() {
        correctionHistory = databaseManager.getRecentCorrections(limit: 10)
    }
    
    func clearHistory() {
        correctionHistory.removeAll()
        databaseManager.clearCorrectionHistory()
    }
    
    // MARK: - Rate Limiting
    
    /// Checks if a new correction is allowed based on rate limits
    /// Returns true if allowed, false if rate limited
    func checkRateLimit() -> Bool {
        cleanupOldTimestamps()
        
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        let correctionsLastMinute = recentCorrectionTimestamps.filter { $0 > oneMinuteAgo }.count
        let correctionsLastHour = recentCorrectionTimestamps.filter { $0 > oneHourAgo }.count
        
        if correctionsLastMinute >= correctionsPerMinuteLimit {
            return false
        }
        
        if correctionsLastHour >= correctionsPerHourLimit {
            return false
        }
        
        // Check spending cap
        if spendingCapEnabled {
            let thisMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!
            let monthlyTokens = databaseManager.getTotalTokensUsed(since: thisMonth)
            let totalMonthlyTokens = monthlyTokens.input + monthlyTokens.output
            
            if totalMonthlyTokens >= monthlyTokenLimit {
                return false
            }
        }
        
        return true
    }
    
    private func cleanupOldTimestamps() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        recentCorrectionTimestamps = recentCorrectionTimestamps.filter { $0 > oneHourAgo }
    }
    
    /// Returns current usage stats for display
    func getCurrentUsageStats() -> (minuteCount: Int, hourCount: Int, monthlyTokens: Int) {
        cleanupOldTimestamps()
        
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let oneHourAgo = now.addingTimeInterval(-3600)
        let thisMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!
        
        let minuteCount = recentCorrectionTimestamps.filter { $0 > oneMinuteAgo }.count
        let hourCount = recentCorrectionTimestamps.filter { $0 > oneHourAgo }.count
        let monthlyTokens = databaseManager.getTotalTokensUsed(since: thisMonth)
        
        return (minuteCount, hourCount, monthlyTokens.input + monthlyTokens.output)
    }

    // MARK: - Icon State Management
    func setIconState(_ state: MenuBarIconState, autoReset: Bool = false, duration: TimeInterval = 3.0) {
        iconResetTimer?.invalidate()
        iconState = state

        if autoReset && state != .normal && state != .processing && state != .noPermission && state != .rateLimited {
            iconResetTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.iconState = .normal
                }
            }
        }
    }
    
    // MARK: - Bookmark Management
    func setBookmark(for fieldSignature: String, bookmark: CorrectionBookmark) {
        correctionBookmarks[fieldSignature] = bookmark
    }
    
    func getBookmark(for fieldSignature: String) -> CorrectionBookmark? {
        return correctionBookmarks[fieldSignature]
    }
    
    func clearBookmark(for fieldSignature: String) {
        correctionBookmarks.removeValue(forKey: fieldSignature)
    }
    
    // MARK: - Persistence Helpers
    private func saveShortcut() {
        if let data = try? JSONEncoder().encode(keyboardShortcut) {
            UserDefaults.standard.set(data, forKey: "keyboardShortcut")
        }
    }
    
    private func saveApiKey() {
        KeychainHelper.save(key: "openai_api_key", value: openAIApiKey)
    }
}

// MARK: - Keyboard Shortcut Configuration
struct KeyboardShortcutConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: Set<ModifierKey>
    
    enum ModifierKey: String, Codable {
        case command
        case shift
        case option
        case control
    }
    
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
    
    private func keyCodeToString(_ code: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
            51: "Delete", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4", 119: "F2",
            120: "F1", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[code] ?? "?"
    }
}

// MARK: - Keychain Helper
struct KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
