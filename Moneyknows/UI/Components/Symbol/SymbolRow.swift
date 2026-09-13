import SwiftUI

struct SymbolRowLayout<Leading: View, Trailing: View>: View {
    var leading: Leading
    var trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                leading
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                trailing
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }
}

enum SymbolRowArrangement {
    case packed
    case distributed
}

struct SymbolRow: View {
    var summary: SymbolSummary
    var accessory: String? = nil
    var arrangement: SymbolRowArrangement = .packed
    var showsATR: Bool = false

    var body: some View {
        Group {
            switch arrangement {
            case .packed:
                packedRow
            case .distributed:
                distributedRow
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var packedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(summary.symbol)
                .font(.headline.weight(.bold))
            Text(MarketFormat.price(summary.lastPrice))
                .font(.headline.monospacedDigit())
            ChangePercentText(
                percent: summary.changePercent,
                font: .subheadline.weight(.semibold).monospacedDigit()
            )
            if let volume = finiteVolume {
                Text(MarketFormat.compact(volume))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            if let accessory {
                Text(accessory)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var distributedRow: some View {
        ScreenerMetricsColumns(showsATR: showsATR) {
            Text(summary.symbol)
                .font(.headline.weight(.bold))
        } atr: {
            Text(MarketFormat.percentUnsigned(summary.atrPercent))
                .font(.subheadline.weight(.bold).monospacedDigit())
        } price: {
            Text(MarketFormat.price(summary.lastPrice))
                .font(metricFont)
        } volume: {
            Text(MarketFormat.compact(finiteVolume))
                .font(metricFont)
                .foregroundColor(.secondary)
        } change: {
            ChangePercentText(
                percent: summary.changePercent,
                font: metricFont.weight(.semibold)
            )
        }
    }

    private var metricFont: Font {
        .subheadline.monospacedDigit()
    }

    private var finiteVolume: Double? {
        guard let volume = summary.volume, volume.isFinite else { return nil }
        return volume
    }
}

private struct ScreenerMetricsColumns<Symbol: View, ATR: View, Price: View, Volume: View, Change: View>: View {
    var showsATR: Bool
    var symbol: Symbol
    var atr: ATR
    var price: Price
    var volume: Volume
    var change: Change

    init(
        showsATR: Bool,
        @ViewBuilder symbol: () -> Symbol,
        @ViewBuilder atr: () -> ATR,
        @ViewBuilder price: () -> Price,
        @ViewBuilder volume: () -> Volume,
        @ViewBuilder change: () -> Change
    ) {
        self.showsATR = showsATR
        self.symbol = symbol()
        self.atr = atr()
        self.price = price()
        self.volume = volume()
        self.change = change()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            cell(alignment: .leading, content: symbol)
            if showsATR {
                cell(alignment: .trailing, content: atr)
            }
            cell(alignment: .trailing, content: price)
            cell(alignment: .trailing, content: volume)
            cell(alignment: .trailing, content: change)
        }
    }

    private func cell<Content: View>(alignment: Alignment, content: Content) -> some View {
        content
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
            .layoutPriority(0)
    }
}
