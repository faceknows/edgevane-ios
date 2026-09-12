import SwiftUI

struct RsiAdxFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenerRSIRangePicker(value: $query.rsiRange, onSelect: { _ in apply() })
            ScreenerADXRangePicker(value: $query.adxRange, onSelect: { _ in apply() })
            HStack(alignment: .top, spacing: 12) {
                ScreenerDIGapPicker(value: $query.diGap, onSelect: { _ in apply() })
                ScreenerDirectionPicker(value: $query.direction, onSelect: { _ in apply() })
            }
            ScreenerTimeFramePicker(value: $query.timeFrame, onSelect: { _ in apply() })
        }
    }
}
