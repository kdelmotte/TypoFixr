import Foundation
import SwiftUI
import Combine

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
    
    // MARK: - Correction History
    @Published var correctionHistory: [Correction] = []
    
    // MARK: - Revert State
    @Published var lastCorrectionTime: Date? = nil
    @Published var canToggleRevert: Bool = false
    private var revertTimer: Timer?
    
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
        self.characterLimit = UserDefaults.standard.object(forKey: "characterLimit") as? Int ?? 500
        self.languagePreference = UserDefaults.standard.string(forKey: "languagePreference") ?? "auto"
        
        // Load shortcut
        if let data = UserDefaults.standard.data(forKey: "keyboardShortcut"),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcutConfig.self, from: data) {
            self.keyboardShortcut = shortcut
        } else {
            // Default: Cmd + Shift + .
            self.keyboardShortcut = KeyboardShortcutConfig(
                keyCode: 47, // Period key
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
        correctionHistory.insert(correction, at: 0)
        
        // Keep only last 10 in memory
        if correctionHistory.count > 10 {
            correctionHistory = Array(correctionHistory.prefix(10))
        }
        
        // Save to database
        databaseManager.saveCorrection(correction)
        
        // Start revert timer
        startRevertTimer()
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
    
    // MARK: - Revert Timer
    private func startRevertTimer() {
        lastCorrectionTime = Date()
        canToggleRevert = true
        
        revertTimer?.invalidate()
        revertTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.canToggleRevert = false
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
