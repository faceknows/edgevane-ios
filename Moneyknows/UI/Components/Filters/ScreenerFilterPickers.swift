import SwiftUI

struct ScreenerDirectionPicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.direction,
            selection: $value,
            options: ScreenerDirection.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerTimeFramePicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.timeFrame,
            selection: $value,
            options: ScreenerTimeFrame.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerMinVolumePicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.minVolume,
            selection: $value,
            options: ScreenerMinVolume.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerMinPricePicker: View {
    @Binding var value: String
    var options: [ScreenerMinPrice] = ScreenerMinPrice.standard
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.minPrice,
            selection: $value,
            options: options.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerBarCountPicker: View {
    @Binding var value: String
    var options: [ScreenerBarCount] = ScreenerBarCount.atr
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.barCount,
            selection: $value,
            options: options.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}
