import SwiftUI

enum MarketFormat {
    static func price(_ value: Double?) -> String {
        guard let value else { return "—" }
        return priceFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.2f%%", value)
    }

    static func changeColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .secondary
    }

    static func compact(_ value: Double?) -> String {
        guard let value else { return "—" }
        if abs(value) >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if abs(value) >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
