import SwiftUI

struct IBKRFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ScreenerIBKRTypePicker(value: $query.ibkrType, onSelect: { _ in apply() })
                ScreenerDatePicker(value: $query.date, onSelect: { _ in apply() })
            }
            HStack(alignment: .top, spacing: 12) {
                ScreenerMinPricePicker(
                    value: $query.minPrice,
                    options: ScreenerMinPrice.ibkr,
                    onSelect: { _ in apply() }
                )
                ScreenerMinMarketCapPicker(value: $query.ibkrMarketCap, onSelect: { _ in apply() })
            }
        }
    }
}
