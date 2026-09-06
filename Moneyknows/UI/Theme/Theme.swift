import SwiftUI
import UIKit

enum AppTheme {
    static let fieldCorner: CGFloat = 10
}

enum ChartPalette {
    static func colors(scheme: ColorScheme) -> ChartColors {
        let dark = scheme == .dark
        return ChartColors(
            background: rgba(background(dark: dark), dark: dark),
            text: rgba(text(dark: dark), dark: dark),
            up: rgba(.systemGreen, dark: dark),
            down: rgba(.systemRed, dark: dark),
            vwap: rgba(.systemBlue, dark: dark),
            prevClose: rgba(UIColor(red: 138 / 255, green: 8 / 255, blue: 91 / 255, alpha: 1), dark: dark),
            sessionOpen: rgba(.systemGreen, dark: dark),
            buy: rgba(.systemGreen, dark: dark),
            sell: rgba(.systemRed, dark: dark),
            other: rgba(dark ? .systemGray : .systemGray2, dark: dark),
            volume: rgba(.systemGray, dark: dark),
            grid: ChartRGBA(red: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: dark ? 0.06 : 0.08)
        )
    }

    private static func background(dark: Bool) -> UIColor {
        dark ? UIColor(white: 0.07, alpha: 1) : .systemBackground
    }

    private static func text(dark: Bool) -> UIColor {
        dark ? UIColor(white: 0.86, alpha: 1) : .label
    }

    private static func rgba(_ color: UIColor, dark: Bool) -> ChartRGBA {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return ChartRGBA(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}
