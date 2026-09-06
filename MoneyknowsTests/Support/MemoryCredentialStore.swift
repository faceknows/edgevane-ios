import Foundation
@testable import Moneyknows

final class MemoryCredentialStore: CredentialStoring {
    private var values: [String: String] = [:]

    func set(_ value: String, account: String) throws {
        values[account] = value
    }

    func string(account: String) -> String? {
        values[account]
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }

    func accounts() -> [String] {
        Array(values.keys)
    }
}
