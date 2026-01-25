import Foundation
import SQLite

// Type alias to avoid conflict with Foundation.Expression (macOS 15+)
typealias SQLExpression = SQLite.Expression

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: Connection?
    private let deviceId: String

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
    
    private init() {
        // Get or create device ID
        if let savedDeviceId = KeychainHelper.load(key: "device_id") {
            self.deviceId = savedDeviceId
        } else {
            let newDeviceId = UUID().uuidString
            KeychainHelper.save(key: "device_id", value: newDeviceId)
            self.deviceId = newDeviceId
        }
        
        setupDatabase()
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
        })
        
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
            try db?.run(correctionHistory.insert(or: .replace,
                correctionId <- correction.id.uuidString,
                timestamp <- correction.timestamp,
                originalText <- correction.originalText,
                correctedText <- correction.correctedText,
                appBundleId <- correction.appBundleId,
                reverted <- correction.reverted,
                inputTokens <- correction.inputTokens,
                outputTokens <- correction.outputTokens
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
                let correction = Correction(
                    id: UUID(uuidString: row[correctionId]) ?? UUID(),
                    timestamp: row[timestamp],
                    originalText: row[originalText],
                    correctedText: row[correctedText],
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
}

struct DatabaseStatistics {
    let correctionsToday: Int
    let correctionsThisMonth: Int
    let tokensUsedToday: Int
    let tokensUsedThisMonth: Int
}
