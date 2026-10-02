import Foundation
import SwiftUI
import Combine

// MARK: - Menu Bar Icon State
enum MenuBarIconState: CaseIterable {
    case normal
    case processing
    case success
    case error
    case noPermission
    case offline

    var statusDescription: String {
        switch self {
        case .normal: return "Ready"
        case .processing: return "Processing"
        case .success: return "Success"
        case .error: return "Error"
        case .noPermission: return "Accessibility Permission Required"
        case .offline: return "Offline"
        }
    }
}

class AppState: ObservableObject {
    // MARK: - Permission State
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            guard oldValue != hasCompletedOnboarding else { return }
            defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
            if hasCompletedOnboarding {
                TelemetryService.shared.track(.onboardingCompleted)
            }
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
            guard oldValue != keyboardShortcut else { return }
            saveShortcut()
            TelemetryService.shared.track(
                .shortcutChanged(isDefault: keyboardShortcut == .defaultConfig)
            )
        }
    }
    @Published var languagePreference: String {
        didSet {
            defaults.set(languagePreference, forKey: "languagePreference")
        }
    }
    
    // MARK: - Security & Privacy Settings
    @Published var securityWarningsEnabled: Bool {
        didSet {
            defaults.set(securityWarningsEnabled, forKey: "securityWarningsEnabled")
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
    let databaseManager: DatabaseManager
    private let defaults: UserDefaults
    private let credentials: any CredentialStore
    
    // MARK: - Initialization
    init(defaults: UserDefaults = .standard,
         databaseManager: DatabaseManager = .shared,
         credentials: any CredentialStore = KeychainStore.shared) {
        self.defaults = defaults
        self.databaseManager = databaseManager
        self.credentials = credentials
        // Load persisted values
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.languagePreference = defaults.string(forKey: "languagePreference") ?? "auto"
        
        // Load security & privacy settings
        self.securityWarningsEnabled = defaults.object(forKey: "securityWarningsEnabled") as? Bool ?? true
        
        // Load shortcut
        if let data = defaults.data(forKey: "keyboardShortcut"),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcutConfig.self, from: data) {
            self.keyboardShortcut = shortcut
        } else {
            self.keyboardShortcut = .defaultConfig
        }
        
        // Load API key from Keychain, but discard obvious placeholder/example values.
        let persistedGroqAPIKey: String?
        var credentialError: Error?
        do { persistedGroqAPIKey = try credentials.load(key: "groq_api_key") }
        catch { persistedGroqAPIKey = nil; credentialError = error }
        let sanitizedGroqAPIKey = GroqAPIKeyValidationState.sanitizedPersistedAPIKey(persistedGroqAPIKey)
        self.groqApiKey = sanitizedGroqAPIKey
        if let credentialError { lastError = credentialError.localizedDescription }

        if (persistedGroqAPIKey ?? "") != sanitizedGroqAPIKey {
            do {
                if sanitizedGroqAPIKey.isEmpty {
                    try credentials.delete(key: "groq_api_key")
                } else {
                    try credentials.save(key: "groq_api_key", value: sanitizedGroqAPIKey)
                }
            } catch { lastError = error.localizedDescription }
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

    /// Apply the current process's trust result, not a saved onboarding flag.
    func updateAccessibilityPermission(isTrusted: Bool, isConnected: Bool) {
        hasAccessibilityPermission = isTrusted
        if isTrusted {
            if lastError == "Accessibility permission required" { lastError = nil }
            if iconState == .noPermission { setIconState(isConnected ? .normal : .offline) }
        } else {
            setIconState(.noPermission)
        }
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
            defaults.set(data, forKey: "keyboardShortcut")
        }
    }
    
    private func saveApiKey() {
        let trimmedApiKey = GroqAPIKeyValidationState.trimmed(groqApiKey)

        do {
            if trimmedApiKey.isEmpty {
                try credentials.delete(key: "groq_api_key")
            } else {
                try credentials.save(key: "groq_api_key", value: trimmedApiKey)
            }
        } catch { lastError = error.localizedDescription }
    }
}

// MARK: - Keyboard Shortcut Configuration
struct KeyboardShortcutConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: Set<ModifierKey>

    static let defaultConfig = KeyboardShortcutConfig(
        keyCode: 2, // D key
        modifiers: [.command, .shift]
    )
    
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
    static let productName = "TypoFixr"
    static let bundleIdentifier = "com.typofixr.app"
    static let keychainService = bundleIdentifier
    static let applicationSupportDirectoryName = "TypoFixr"
    static let databaseFileName = "typo_fixr.db"
    static let feedbackEmail = "feedback@typofixr.com"

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func requestAccessibilityPermission(source: AccessibilityGrantSource) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            openAccessibilitySettings()
            return
        }

        appDelegate.requestAccessibilityPermission(source: source)
    }
}

/// Xcode hosts unit tests inside the app executable. Keep that host out of the
/// real Keychain, preferences and database before XCTest loads any test fixtures.
enum AppRuntime {
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["TYPOFIXR_TESTING"] == "1" || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }

    static func makeAppState() -> AppState {
        guard isRunningTests else { return AppState() }
        let defaults = UserDefaults(suiteName: "TypoFixrTestHost.\(UUID().uuidString)")!
        // Failure to allocate ephemeral storage must never fall back to production.
        let database = try! DatabaseManager(path: ":memory:", deviceID: "test-host")
        return AppState(defaults: defaults, databaseManager: database, credentials: MemoryCredentialStore())
    }
}
