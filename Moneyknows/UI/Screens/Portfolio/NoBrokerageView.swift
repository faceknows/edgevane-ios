import SwiftUI

struct NoBrokerageView: View {
    var body: some View {
        TradingCredentialsPrompt(
            title: L10n.Dashboard.noBrokerage,
            message: L10n.Trading.addCredentialsBody
        )
    }
}
