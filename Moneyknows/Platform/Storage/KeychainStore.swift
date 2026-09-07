import Foundation
import Security

protocol CredentialStoring {
    func set(_ value: String, account: String) throws
    func string(account: String) -> String?
    func stringIfPresent(account: String) throws -> String?
    func delete(account: String)
    func deleteChecked(account: String) throws
    func accounts() throws -> [String]
}

extension CredentialStoring {
    func stringIfPresent(account: String) throws -> String? {
        string(account: account)
    }

    func deleteChecked(account: String) throws {
        delete(account: account)
        guard string(account: account) == nil else {
            throw AppError.decoding
        }
    }
}

struct KeychainStore: CredentialStoring {
    var service: String

    func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.decoding
        }
    }

    func string(account: String) -> String? {
        try? stringIfPresent(account: account)
    }

    func stringIfPresent(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AppError.decoding
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw AppError.decoding
        }
        return value
    }

    func delete(account: String) {
        _ = deleteStatus(account: account)
    }

    func deleteChecked(account: String) throws {
        let status = deleteStatus(account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.decoding
        }
        guard try stringIfPresent(account: account) == nil else {
            throw AppError.decoding
        }
    }

    func accounts() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw AppError.decoding
        }
        if let items = result as? [[String: Any]] {
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        }
        if let item = result as? [String: Any], let account = item[kSecAttrAccount as String] as? String {
            return [account]
        }
        return []
    }

    private func deleteStatus(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
