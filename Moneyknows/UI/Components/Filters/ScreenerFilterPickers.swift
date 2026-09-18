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

struct ScreenerSpanPicker: View {
    @Binding var value: String
    var options: [ScreenerSpanMinutes] = ScreenerSpanMinutes.allCases
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.window,
            selection: $value,
            options: options.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerRSIRangePicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.rsi,
            selection: $value,
            options: ScreenerRSIRange.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerADXRangePicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.adx,
            selection: $value,
            options: ScreenerADXRange.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerDIGapPicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.diGap,
            selection: $value,
            options: ScreenerDIGap.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerIBKRTypePicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.scanType,
            selection: $value,
            options: ScreenerIBKRType.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerMinMarketCapPicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        TappableValueField(
            title: L10n.Market.minMarketCap,
            selection: $value,
            options: ScreenerMinMarketCap.allCases.map {
                TappableOption(value: $0.rawValue, title: $0.title)
            },
            onSelect: onSelect
        )
    }
}

struct ScreenerDatePicker: View {
    @Binding var value: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Market.date)
                .font(.caption)
                .foregroundColor(.secondary)
            DatePicker(
                "",
                selection: dateBinding,
                displayedComponents: .date
            )
            .environment(\.timeZone, MarketClock.easternTimeZone)
            .datePickerStyle(.compact)
            .labelsHidden()
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { MarketClock.date(fromUSDate: value) ?? Date() },
            set: { next in
                let date = MarketClock.usDateString(from: next)
                guard date != value else { return }
                value = date
                onSelect?(date)
            }
        )
    }
}
