import SwiftUI

struct PriceSlopeFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenerDirectionPicker(value: $query.direction, onSelect: { _ in apply() })
            ScreenerSpanPicker(value: $query.spanMinutes, onSelect: { _ in apply() })
            HStack(alignment: .center, spacing: 12) {
                ScreenerMinPricePicker(value: $query.minPrice, onSelect: { _ in apply() })
                ScreenerMinVolumePicker(value: $query.minVolume, onSelect: { _ in apply() })
            }
        }
    }
}
