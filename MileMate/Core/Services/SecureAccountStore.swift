import Foundation
import Security

protocol SecureAccountStoring: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}

enum SecureAccountStoreError: Error {
    case keychain(OSStatus)
}

struct KeychainAccountStore: SecureAccountStoring {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.fikrutibebe.milemate") {
        self.service = service
    }

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureAccountStoreError.keychain(status) }
        return item as? Data
    }

    func set(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)
        let attributes = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard insertionStatus == errSecSuccess else {
                throw SecureAccountStoreError.keychain(insertionStatus)
            }
        } else if status != errSecSuccess {
            throw SecureAccountStoreError.keychain(status)
        }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureAccountStoreError.keychain(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

#if DEBUG
final class InMemoryAccountStore: SecureAccountStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(for key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func set(_ data: Data, for key: String) throws {
        lock.withLock { values[key] = data }
    }

    func remove(_ key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}
#endif
