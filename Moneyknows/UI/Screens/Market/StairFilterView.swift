import SwiftUI

struct StairFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ScreenerDirectionPicker(value: $query.direction, onSelect: { _ in apply() })
                ScreenerTimeFramePicker(value: $query.timeFrame, onSelect: { _ in apply() })
            }
            ScreenerBarCountPicker(
                value: $query.barCount,
                options: ScreenerBarCount.stair,
                onSelect: { _ in apply() }
            )
            HStack(alignment: .center, spacing: 12) {
                ScreenerMinPricePicker(value: $query.minPrice, onSelect: { _ in apply() })
                ScreenerMinVolumePicker(value: $query.minVolume, onSelect: { _ in apply() })
            }
        }
    }
}
