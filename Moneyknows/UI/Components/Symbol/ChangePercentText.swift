import SwiftUI

struct ChangePercentText: View {
    var percent: Double?
    var font: Font = .subheadline.monospacedDigit()

    var body: some View {
        Text(MarketFormat.percent(percent))
            .font(font)
            .foregroundColor(MarketFormat.changeColor(percent))
    }
}
