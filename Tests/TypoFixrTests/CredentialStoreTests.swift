import XCTest
import Security
@testable import TypoFixr

private final class TestKeychain: KeychainAccess {
    var values: [String: Data] = [:]
    var queries: [[String: Any]] = []
    var writeError: OSStatus?

    private func key(_ query: CFDictionary) -> String {
        let query = query as! [String: Any]
        queries.append(query)
        return "\(query[kSecAttrService as String] ?? "UNSCOPED")|\(query[kSecAttrAccount as String] ?? "")"
    }
    func read(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus {
        guard let data = values[key(query)] else { return errSecItemNotFound }
        result = data as CFData
        return errSecSuccess
    }
    func add(_ attributes: CFDictionary) -> OSStatus {
        let id = key(attributes)
        if let writeError { return writeError }
        values[id] = (attributes as NSDictionary)[kSecValueData] as? Data
        return errSecSuccess
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        let id = key(query)
        if let writeError { return writeError }
        guard values[id] != nil else { return errSecItemNotFound }
        values[id] = (attributes as NSDictionary)[kSecValueData] as? Data
        return errSecSuccess
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        values.removeValue(forKey: key(query)) == nil ? errSecItemNotFound : errSecSuccess
    }
}

final class CredentialStoreTests: XCTestCase {
    func testMissingCredentialDoesNotReadAnotherService() throws {
        let keychain = TestKeychain()
        keychain.values["old.app|groq_api_key"] = Data("old-key".utf8)
        let store = KeychainStore(service: "new.app", access: keychain)
        XCTAssertNil(try store.load(key: "groq_api_key"))
        XCTAssertEqual(keychain.queries.count, 1)
        XCTAssertEqual(keychain.queries.first?[kSecAttrService as String] as? String, "new.app")
    }

    func testDeleteOnlyRemovesThisAppsCredential() throws {
        let keychain = TestKeychain()
        keychain.values["old.app|groq_api_key"] = Data("old-key".utf8)
        keychain.values["new.app|groq_api_key"] = Data("new-key".utf8)
        let store = KeychainStore(service: "new.app", access: keychain)
        try store.delete(key: "groq_api_key")
        XCTAssertNil(keychain.values["new.app|groq_api_key"])
        XCTAssertEqual(keychain.values["old.app|groq_api_key"], Data("old-key".utf8))
        XCTAssertEqual(keychain.queries.count, 1)
    }

    func testSaveAddsThenUpdatesWithoutDeleting() throws {
        let keychain = TestKeychain()
        let store = KeychainStore(service: "new.app", access: keychain)
        try store.save(key: "groq_api_key", value: "first")
        try store.save(key: "groq_api_key", value: "second")
        XCTAssertEqual(try store.load(key: "groq_api_key"), "second")
        XCTAssertTrue(keychain.queries.allSatisfy { $0[kSecAttrService as String] as? String == "new.app" })
    }

    func testSaveFailurePreservesExistingCredentialAndReportsError() {
        let keychain = TestKeychain()
        keychain.values["new.app|groq_api_key"] = Data("original".utf8)
        keychain.writeError = errSecAuthFailed
        let store = KeychainStore(service: "new.app", access: keychain)
        XCTAssertThrowsError(try store.save(key: "groq_api_key", value: "replacement"))
        XCTAssertEqual(keychain.values["new.app|groq_api_key"], Data("original".utf8))
    }

    func testScopedPublicCredentialTakesPriorityOverLegacy() throws {
        let keychain = TestKeychain()
        keychain.values["com.typofixr.app|groq_api_key"] = Data("current".utf8)
        keychain.values["|groq_api_key"] = Data("legacy".utf8)
        let store = KeychainStore(access: keychain)
        XCTAssertEqual(try store.load(key: "groq_api_key"), "current")
        XCTAssertEqual(keychain.queries.count, 1)
    }

    func testLegacyMigrationOnlyMovesEmptyServiceCredential() throws {
        let keychain = TestKeychain()
        keychain.values["|groq_api_key"] = Data("legacy".utf8)
        keychain.values["other.app|groq_api_key"] = Data("unrelated".utf8)
        let store = KeychainStore(access: keychain)
        XCTAssertEqual(try store.load(key: "groq_api_key"), "legacy")
        XCTAssertEqual(keychain.values["com.typofixr.app|groq_api_key"], Data("legacy".utf8))
        XCTAssertNil(keychain.values["|groq_api_key"])
        XCTAssertEqual(keychain.values["other.app|groq_api_key"], Data("unrelated".utf8))
        XCTAssertTrue(keychain.queries.allSatisfy { $0[kSecAttrService as String] != nil })
    }

    func testFailedMigrationLeavesLegacyCredentialIntact() {
        let keychain = TestKeychain()
        keychain.values["|device_id"] = Data("legacy-device".utf8)
        keychain.writeError = errSecAuthFailed
        let store = KeychainStore(access: keychain)
        XCTAssertThrowsError(try store.load(key: "device_id"))
        XCTAssertEqual(keychain.values["|device_id"], Data("legacy-device".utf8))
        XCTAssertNil(keychain.values["com.typofixr.app|device_id"])
    }

    func testDeleteRemovesExactLegacyItemWithoutTouchingOtherServices() throws {
        let keychain = TestKeychain()
        keychain.values["com.typofixr.app|groq_api_key"] = Data("current".utf8)
        keychain.values["|groq_api_key"] = Data("legacy".utf8)
        keychain.values["other.app|groq_api_key"] = Data("unrelated".utf8)
        let store = KeychainStore(access: keychain)
        try store.delete(key: "groq_api_key")
        XCTAssertNil(try store.load(key: "groq_api_key"))
        XCTAssertEqual(keychain.values["other.app|groq_api_key"], Data("unrelated".utf8))
        XCTAssertTrue(keychain.queries.allSatisfy { $0[kSecAttrService as String] != nil })
    }

    func testMissingPublicCredentialDoesNotImportAnotherAppsValue() throws {
        let keychain = TestKeychain()
        keychain.values["other.app|groq_api_key"] = Data("unrelated".utf8)
        let store = KeychainStore(access: keychain)
        XCTAssertNil(try store.load(key: "groq_api_key"))
        XCTAssertEqual(keychain.queries.compactMap { $0[kSecAttrService as String] as? String }, ["com.typofixr.app", ""])
    }

    func testUnknownAccountDoesNotUseLegacyMigration() throws {
        let keychain = TestKeychain()
        keychain.values["|unrelated_account"] = Data("unrelated".utf8)
        let store = KeychainStore(access: keychain)
        XCTAssertNil(try store.load(key: "unrelated_account"))
        XCTAssertEqual(keychain.queries.count, 1)
    }
}
