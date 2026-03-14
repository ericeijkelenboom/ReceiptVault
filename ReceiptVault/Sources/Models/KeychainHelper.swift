import Foundation
import Security

enum KeychainHelper {
    static func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func write(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ReceiptVaultError.parseFailure("Keychain write failed: \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            throw ReceiptVaultError.parseFailure("Keychain update failed: \(updateStatus)")
        }
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

#if DEBUG
// For testing: allow swapping Security framework for a mock
protocol KeychainService {
    func read(key: String) -> String?
    func write(key: String, value: String) throws
    func delete(key: String)
}

class RealKeychainService: KeychainService {
    func read(key: String) -> String? {
        KeychainHelper.read(key: key)
    }

    func write(key: String, value: String) throws {
        try KeychainHelper.write(key: key, value: value)
    }

    func delete(key: String) {
        KeychainHelper.delete(key: key)
    }
}

class MockKeychainService: KeychainService {
    private var storage: [String: String] = [:]

    func read(key: String) -> String? {
        storage[key]
    }

    func write(key: String, value: String) throws {
        storage[key] = value
    }

    func delete(key: String) {
        storage.removeValue(forKey: key)
    }
}
#endif
