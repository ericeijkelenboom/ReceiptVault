import XCTest
@testable import ReceiptVault

class KeychainHelperTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clean up test keychain entries before each test
        KeychainHelper.delete(key: "test_key")
    }

    func test_write_and_read_success() throws {
        let testKey = "test_key"
        let testValue = "test_value_123"

        try KeychainHelper.write(key: testKey, value: testValue)
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertEqual(retrieved, testValue, "Should retrieve the exact value written")
    }

    func test_read_nonexistent_key_returnsNil() {
        let result = KeychainHelper.read(key: "nonexistent_key_xyz")
        XCTAssertNil(result, "Reading non-existent key should return nil")
    }

    func test_delete_removes_value() throws {
        let testKey = "test_delete_key"
        let testValue = "value_to_delete"

        try KeychainHelper.write(key: testKey, value: testValue)
        KeychainHelper.delete(key: testKey)
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertNil(retrieved, "After delete, reading should return nil")
    }

    func test_overwrite_updates_value() throws {
        let testKey = "test_overwrite"

        try KeychainHelper.write(key: testKey, value: "value_1")
        try KeychainHelper.write(key: testKey, value: "value_2")
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertEqual(retrieved, "value_2", "Overwriting should update the value")
    }

    func test_write_empty_string() throws {
        let testKey = "test_empty"

        try KeychainHelper.write(key: testKey, value: "")
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertEqual(retrieved, "", "Should handle empty strings")
    }
}
