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

            Picker(L10n.Market.direction, selection: $query.direction) {
                Text(L10n.Market.up).tag("up")
                Text(L10n.Market.down).tag("down")
            }
            .pickerStyle(.segmented)

            Picker(L10n.Market.window, selection: $query.spanMinutes) {
                ForEach(["15", "30", "60", "90", "120"], id: \.self) { value in
                    Text(value).tag(value)
                }
            }

            Picker(L10n.Market.minPrice, selection: $query.minPrice) {
                ForEach(["4", "6", "8", "10"], id: \.self) { value in
                    Text(value).tag(value)
                }
            }

            Picker(L10n.Market.minVolume, selection: $query.minVolume) {
                ForEach(["1M", "2M", "5M", "10M"], id: \.self) { value in
                    Text(value).tag(value)
                }
            }

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
