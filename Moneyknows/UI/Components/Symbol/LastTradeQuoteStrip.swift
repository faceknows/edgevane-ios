import SwiftUI

/// Last trade on the left; live bid/ask (and sizes when present) on the right.
struct LastTradeQuoteStrip: View {
    var lastPrice: Double?
    var quote: SymbolQuote?
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(MarketFormat.price(lastPrice))
                .font(compact ? .title3.bold() : .title.bold())
                .monospacedDigit()
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.Trading.quoteLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                if let bid = quote?.liveBid, let ask = quote?.liveAsk {
                    quoteSide(price: bid, size: quote?.displayBidSize)
                    Text("|")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    quoteSide(price: ask, size: quote?.displayAskSize)
                } else {
                    Text("—")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func quoteSide(price: Double, size: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(MarketFormat.price(price))
                .font(.headline.monospacedDigit())
            if let size {
                Text(MarketFormat.quantity(size))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
