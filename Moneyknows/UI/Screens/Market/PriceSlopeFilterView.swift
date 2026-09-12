import SwiftUI

struct PriceSlopeFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                L10n.Market.date,
                selection: dateBinding,
                displayedComponents: .date
            )
            .environment(\.timeZone, MarketClock.easternTimeZone)

            ScreenerDirectionPicker(value: $query.direction)

            TappableValueField(
                title: L10n.Market.window,
                selection: $query.spanMinutes,
                options: ["15", "30", "60", "90", "120"].map {
                    TappableOption(value: $0, title: $0)
                }
            )

            ScreenerMinPricePicker(value: $query.minPrice)

            ScreenerMinVolumePicker(value: $query.minVolume)

            HStack {
                Text(L10n.Market.endTime)
                TextField("09:30", text: $query.endTime)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
            }

            Button(L10n.Market.applyFilters, action: apply)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { MarketClock.date(fromUSDate: query.date) ?? Date() },
            set: { query.date = MarketClock.usDateString(from: $0) }
        )
    }
}
