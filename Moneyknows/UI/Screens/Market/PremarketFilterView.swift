import SwiftUI

struct PremarketFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ScreenerDirectionPicker(value: $query.direction, onSelect: { _ in apply() })
                ScreenerSpanPicker(
                    value: $query.spanMinutes,
                    options: ScreenerSpanMinutes.premarket,
                    onSelect: { _ in apply() }
                )
            }
        }
    }
}
