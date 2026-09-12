import SwiftUI

struct MomentumFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ScreenerDirectionPicker(value: $query.direction, onSelect: { _ in apply() })
                ScreenerTimeFramePicker(value: $query.timeFrame, onSelect: { _ in apply() })
            }
            ScreenerMinVolumePicker(value: $query.minVolume, onSelect: { _ in apply() })
        }
    }
}
