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

    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }
}
