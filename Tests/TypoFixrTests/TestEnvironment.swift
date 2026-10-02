import Foundation
@testable import TypoFixr

final class TestEnvironment {
    let defaults: UserDefaults
    let database: DatabaseManager
    let credentials = MemoryCredentialStore()
    private let suite = "TypoFixrTests.\(UUID().uuidString)"

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        database = try DatabaseManager(path: ":memory:", deviceID: UUID().uuidString)
    }

    func makeAppState() -> AppState {
        AppState(defaults: defaults, databaseManager: database, credentials: credentials)
    }

    deinit { defaults.removePersistentDomain(forName: suite) }
}
