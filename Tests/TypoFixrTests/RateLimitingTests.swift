import XCTest
@testable import TypoFixr

final class RateLimitingTests: XCTestCase {
    
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        // Reset rate limit settings
        appState.correctionsPerMinuteLimit = 15
        appState.correctionsPerHourLimit = 100
    }
    
    override func tearDown() {
        appState = nil
        super.tearDown()
    }
    
    func testInitialRateLimitAllowed() {
        XCTAssertTrue(appState.checkRateLimit(), "Initial request should be allowed")
    }
    
    func testRateLimitAfterMultipleCorrections() {
        // Set a low limit for testing
        appState.correctionsPerMinuteLimit = 3
        
        // Add corrections to simulate usage
        for _ in 0..<3 {
            let correction = Correction(originalText: "test", correctedText: "test")
            appState.addCorrection(correction)
        }
        
        // Should be rate limited now
        XCTAssertFalse(appState.checkRateLimit(), "Should be rate limited after exceeding per-minute limit")
    }
    
    func testUsageStatsTracking() {
        let correction = Correction(originalText: "test", correctedText: "test")
        appState.addCorrection(correction)
        
        let stats = appState.getCurrentUsageStats()
        XCTAssertGreaterThanOrEqual(stats.minuteCount, 1, "Should track at least 1 correction in the minute")
    }
}
