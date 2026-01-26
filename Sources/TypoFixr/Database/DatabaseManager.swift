import Foundation
import SQLite
import CryptoKit

// Type alias to avoid conflict with Foundation.Expression (macOS 15+)
typealias SQLExpression = SQLite.Expression

// MARK: - Crypto Helper for Database Encryption
struct CryptoHelper {
    private static let keychainKey = "db_encryption_key"
    
    /// Gets or creates the encryption key from Keychain
    static func getEncryptionKey() -> SymmetricKey {
        // Try to load existing key
        if let keyData = loadKeyFromKeychain() {
            return SymmetricKey(data: keyData)
        }
        
        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        return newKey
    }
    
    /// Encrypts a string using AES-GCM
    static func encrypt(_ plaintext: String) -> String? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        
        do {
            let key = getEncryptionKey()
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else { return nil }
            return combined.base64EncodedString()
        } catch {
            print("Encryption failed: \(error)")
            return nil
        }
    }
    
    /// Decrypts an AES-GCM encrypted string
    static func decrypt(_ ciphertext: String) -> String? {
        guard let data = Data(base64Encoded: ciphertext) else { return nil }
        
        do {
            let key = getEncryptionKey()
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            print("Decryption failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Keychain Operations for Encryption Key
    
    private static func loadKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecAttrService as String: "com.typofixr.encryption",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return data
    }
    
    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecAttrService as String: "com.typofixr.encryption",
            kSecValueData as String: keyData
        ]
        
        // Delete any existing key first
        SecItemDelete(query as CFDictionary)
        
        // Add new key
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to save encryption key: \(status)")
        }
    }
}

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: Connection?
    private let deviceId: String
    
    // Flag to determine if encryption is enabled
    private var encryptionEnabled: Bool = true

    // MARK: - Tables
    private let usageLog = Table("usage_log")
    private let correctionHistory = Table("correction_history")

    // MARK: - Usage Log Columns
    private let id = SQLExpression<Int64>("id")
    private let deviceIdCol = SQLExpression<String>("device_id")
    private let timestamp = SQLExpression<Date>("timestamp")
    private let inputTokens = SQLExpression<Int?>("input_tokens")
    private let outputTokens = SQLExpression<Int?>("output_tokens")
    private let appBundleId = SQLExpression<String?>("app_bundle_id")
    private let success = SQLExpression<Bool>("success")

    // MARK: - Correction History Columns
    private let correctionId = SQLExpression<String>("correction_id")
    private let originalText = SQLExpression<String>("original_text")
    private let correctedText = SQLExpression<String>("corrected_text")
    private let reverted = SQLExpression<Bool>("reverted")
    private let isEncrypted = SQLExpression<Bool>("is_encrypted")
    
    private init() {
        // Get or create device ID
        if let savedDeviceId = KeychainHelper.load(key: "device_id") {
            self.deviceId = savedDeviceId
        } else {
            let newDeviceId = UUID().uuidString
            KeychainHelper.save(key: "device_id", value: newDeviceId)
            self.deviceId = newDeviceId
        }
        
        // Load encryption preference (disabled by default for now)
        self.encryptionEnabled = UserDefaults.standard.object(forKey: "encryptionEnabled") as? Bool ?? false
        
        setupDatabase()
    }
    
    // MARK: - Encryption Helpers
    
    private func encryptText(_ text: String) -> String {
        guard encryptionEnabled else { return text }
        return CryptoHelper.encrypt(text) ?? text
    }
    
    private func decryptText(_ text: String, wasEncrypted: Bool) -> String {
        guard wasEncrypted else { return text }
        return CryptoHelper.decrypt(text) ?? text
    }
    
    private func setupDatabase() {
        do {
            let path = getDatabasePath()
            db = try Connection(path)
            try createTables()
            print("Database initialized at: \(path)")
        } catch {
            print("Database initialization failed: \(error)")
        }
    }
    
    private func getDatabasePath() -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("TypoFixr")
        
        // Create directory if needed
        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder.appendingPathComponent("typo_fixr.db").path
    }
    
    private func createTables() throws {
        // Create usage_log table
        try db?.run(usageLog.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(deviceIdCol)
            t.column(timestamp, defaultValue: Date())
            t.column(inputTokens)
            t.column(outputTokens)
            t.column(appBundleId)
            t.column(success)
        })
        
        // Create correction_history table
        try db?.run(correctionHistory.create(ifNotExists: true) { t in
            t.column(correctionId, primaryKey: true)
            t.column(timestamp, defaultValue: Date())
            t.column(originalText)
            t.column(correctedText)
            t.column(appBundleId)
            t.column(reverted, defaultValue: false)
            t.column(inputTokens)
            t.column(outputTokens)
            t.column(isEncrypted, defaultValue: false)
        })
        
        // Add is_encrypted column to existing tables (migration)
        do {
            try db?.run(correctionHistory.addColumn(isEncrypted, defaultValue: false))
        } catch {
            // Column already exists, ignore error
        }
        
        // Create indexes
        try db?.run(usageLog.createIndex(timestamp, ifNotExists: true))
        try db?.run(correctionHistory.createIndex(timestamp, ifNotExists: true))
    }
    
    // MARK: - Usage Logging
    func logUsage(
        inputTokenCount: Int?,
        outputTokenCount: Int?,
        app: String?,
        wasSuccessful: Bool
    ) {
        do {
            try db?.run(usageLog.insert(
                deviceIdCol <- deviceId,
                timestamp <- Date(),
                inputTokens <- inputTokenCount,
                outputTokens <- outputTokenCount,
                appBundleId <- app,
                success <- wasSuccessful
            ))
        } catch {
            print("Failed to log usage: \(error)")
        }
    }
    
    func getTotalTokensUsed(since date: Date) -> (input: Int, output: Int) {
        guard let db = db else { return (0, 0) }
        do {
            let query = usageLog
                .filter(timestamp >= date)
                .filter(deviceIdCol == deviceId)

            var totalInput = 0
            var totalOutput = 0

            for row in try db.prepare(query) {
                totalInput += row[inputTokens] ?? 0
                totalOutput += row[outputTokens] ?? 0
            }

            return (totalInput, totalOutput)
        } catch {
            print("Failed to get token usage: \(error)")
            return (0, 0)
        }
    }

    func getCorrectionCount(since date: Date) -> Int {
        guard let db = db else { return 0 }
        do {
            let query = usageLog
                .filter(timestamp >= date)
                .filter(deviceIdCol == deviceId)
                .filter(success == true)

            return try db.scalar(query.count)
        } catch {
            print("Failed to get correction count: \(error)")
            return 0
        }
    }
    
    // MARK: - Correction History
    func saveCorrection(_ correction: Correction) {
        do {
            // Encrypt text fields if encryption is enabled
            let encryptedOriginal = encryptText(correction.originalText)
            let encryptedCorrected = encryptText(correction.correctedText)
            
            try db?.run(correctionHistory.insert(or: .replace,
                correctionId <- correction.id.uuidString,
                timestamp <- correction.timestamp,
                originalText <- encryptedOriginal,
                correctedText <- encryptedCorrected,
                appBundleId <- correction.appBundleId,
                reverted <- correction.reverted,
                inputTokens <- correction.inputTokens,
                outputTokens <- correction.outputTokens,
                isEncrypted <- encryptionEnabled
            ))
            
            // Also log to usage
            logUsage(
                inputTokenCount: correction.inputTokens,
                outputTokenCount: correction.outputTokens,
                app: correction.appBundleId,
                wasSuccessful: true
            )
        } catch {
            print("Failed to save correction: \(error)")
        }
    }
    
    func getRecentCorrections(limit: Int = 10) -> [Correction] {
        guard let db = db else { return [] }
        do {
            let query = correctionHistory
                .order(timestamp.desc)
                .limit(limit)

            var corrections: [Correction] = []

            for row in try db.prepare(query) {
                let wasEncrypted = row[isEncrypted]
                let decryptedOriginal = decryptText(row[originalText], wasEncrypted: wasEncrypted)
                let decryptedCorrected = decryptText(row[correctedText], wasEncrypted: wasEncrypted)
                
                let correction = Correction(
                    id: UUID(uuidString: row[correctionId]) ?? UUID(),
                    timestamp: row[timestamp],
                    originalText: decryptedOriginal,
                    correctedText: decryptedCorrected,
                    appBundleId: row[appBundleId],
                    reverted: row[reverted],
                    inputTokens: row[inputTokens],
                    outputTokens: row[outputTokens]
                )
                corrections.append(correction)
            }

            return corrections
        } catch {
            print("Failed to get recent corrections: \(error)")
            return []
        }
    }
    
    func markCorrectionReverted(_ id: UUID) {
        do {
            let correction = correctionHistory.filter(correctionId == id.uuidString)
            try db?.run(correction.update(reverted <- true))
        } catch {
            print("Failed to mark correction as reverted: \(error)")
        }
    }
    
    // MARK: - Statistics
    func getStatistics() -> DatabaseStatistics {
        let today = Calendar.current.startOfDay(for: Date())
        let thisMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        
        let todayCount = getCorrectionCount(since: today)
        let monthCount = getCorrectionCount(since: thisMonth)
        let todayTokens = getTotalTokensUsed(since: today)
        let monthTokens = getTotalTokensUsed(since: thisMonth)
        
        return DatabaseStatistics(
            correctionsToday: todayCount,
            correctionsThisMonth: monthCount,
            tokensUsedToday: todayTokens.input + todayTokens.output,
            tokensUsedThisMonth: monthTokens.input + monthTokens.output
        )
    }
    
    // MARK: - Device ID
    func getDeviceId() -> String {
        return deviceId
    }
    
    // MARK: - Clear History
    func clearCorrectionHistory() {
        do {
            try db?.run(correctionHistory.delete())
            print("Correction history cleared")
        } catch {
            print("Failed to clear correction history: \(error)")
        }
    }
    
    // MARK: - Encryption Settings
    func setEncryptionEnabled(_ enabled: Bool) {
        encryptionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "encryptionEnabled")
    }
    
    func isEncryptionEnabled() -> Bool {
        return encryptionEnabled
    }
}

struct DatabaseStatistics {
    let correctionsToday: Int
    let correctionsThisMonth: Int
    let tokensUsedToday: Int
    let tokensUsedThisMonth: Int
}
