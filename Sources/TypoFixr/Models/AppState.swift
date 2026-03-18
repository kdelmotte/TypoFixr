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

    // MARK: - Settings
    static let characterLimit = 5000
    
    @Published var keyboardShortcut: KeyboardShortcutConfig {
        didSet {
            saveShortcut()
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
    
    // MARK: - API Configuration
    @Published var groqApiKey: String {
        didSet {
            saveApiKey()
        }
    }

    /// Validates that the API key is present and has the expected format
    var hasValidApiKey: Bool {
        GroqAPIKeyValidationState(apiKey: groqApiKey) == .valid
    }

    // MARK: - Database
    let databaseManager = DatabaseManager.shared
    
    // MARK: - Initialization
    init() {
        // Load persisted values
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.languagePreference = UserDefaults.standard.string(forKey: "languagePreference") ?? "auto"
        
        // Load security & privacy settings
        self.securityWarningsEnabled = UserDefaults.standard.object(forKey: "securityWarningsEnabled") as? Bool ?? true
        
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
        
        // Load API key from Keychain, but discard obvious placeholder/example values.
        let persistedGroqAPIKey = KeychainHelper.load(key: "groq_api_key")
        let sanitizedGroqAPIKey = GroqAPIKeyValidationState.sanitizedPersistedAPIKey(persistedGroqAPIKey)
        self.groqApiKey = sanitizedGroqAPIKey

        if (persistedGroqAPIKey ?? "") != sanitizedGroqAPIKey {
            KeychainHelper.delete(key: "groq_api_key")
        }

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

    // MARK: - Icon State Management
    func setIconState(_ state: MenuBarIconState, autoReset: Bool = false, duration: TimeInterval = 3.0) {
        iconResetTimer?.invalidate()
        iconState = state

        if autoReset && state != .normal && state != .processing && state != .noPermission {
            iconResetTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.iconState = .normal
                }
            }
        }
    }

    // MARK: - Persistence Helpers
    private func saveShortcut() {
        if let data = try? JSONEncoder().encode(keyboardShortcut) {
            UserDefaults.standard.set(data, forKey: "keyboardShortcut")
        }
    }
    
    private func saveApiKey() {
        let trimmedApiKey = GroqAPIKeyValidationState.trimmed(groqApiKey)

        if trimmedApiKey.isEmpty {
            KeychainHelper.delete(key: "groq_api_key")
        } else {
            KeychainHelper.save(key: "groq_api_key", value: trimmedApiKey)
        }
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
    
    // Single source of truth for key code → display string mapping.
    // HotkeyService has a separate mapping to HotKey.Key enum values.
    static let keyCodeDisplayNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "Delete", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 118: "F4", 119: "End",
        120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyCodeDisplayNames[keyCode] ?? "?")
        return parts.joined()
    }
}

// MARK: - Shared Helpers
enum AppHelpers {
    static let feedbackEmail = "feedback@typofixr.com"

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Keychain Helper
struct KeychainHelper {
    private static let service = "com.typofixr.app"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        // Try scoped query first
        let scopedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        var status = SecItemCopyMatching(scopedQuery as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        // Fall back to legacy unscoped query (pre-1.3.0 items)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        result = nil
        status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Migrate: re-save with service scope (save() deletes-then-adds)
        save(key: key, value: value)

        return value
    }

    static func delete(key: String) {
        let scopedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(scopedQuery as CFDictionary)

        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(legacyQuery as CFDictionary)
    }

}
