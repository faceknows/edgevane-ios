import SwiftUI

struct ATRFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ScreenerTimeFramePicker(value: $query.timeFrame, onSelect: { _ in apply() })
                ScreenerBarCountPicker(
                    value: $query.barCount,
                    options: ScreenerBarCount.atr,
                    onSelect: { _ in apply() }
                )
            }
            HStack(alignment: .top, spacing: 12) {
                ScreenerMinPricePicker(
                    value: $query.minPrice,
                    options: ScreenerMinPrice.atr,
                    onSelect: { _ in apply() }
                )
                ScreenerMinVolumePicker(value: $query.minVolume, onSelect: { _ in apply() })
            }
        }
    }
}
