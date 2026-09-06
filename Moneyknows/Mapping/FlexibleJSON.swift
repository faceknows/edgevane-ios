import Foundation

enum FlexibleJSON {
    static func decodeDouble<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return finite(value)
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let raw = try? container.decode(String.self, forKey: key),
           let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return finite(value)
        }
        return nil
    }

    static func decodeTimestampRaw<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> String? {
        if let raw = try? container.decode(String.self, forKey: key) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? container.decode(Double.self, forKey: key), value.isFinite {
            if let exact = Int64(exactly: value) {
                return String(exact)
            }
            return String(value)
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }
}
