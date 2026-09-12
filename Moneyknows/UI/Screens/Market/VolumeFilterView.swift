import SwiftUI

struct VolumeFilterView: View {
    @Binding var query: ScreenerQuery
    var apply: () -> Void

    var body: some View {
        ScreenerMinVolumePicker(value: $query.minVolume, onSelect: { _ in apply() })
    }
}
