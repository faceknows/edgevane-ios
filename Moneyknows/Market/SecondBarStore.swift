import Foundation

@MainActor
final class SecondBarStore: ObservableObject {
    static let capacity = 10 * 60

    @Published private(set) var revision: UInt64 = 0

    private var buffers: [String: [Bar]] = [:]
    private var cumulative: [String: (key: String, volume: Double)] = [:]

    func reset() {
        buffers = [:]
        cumulative = [:]
        revision += 1
    }

    func remove(_ symbols: [String]) {
        var changed = false
        for symbol in symbols.map(SymbolCode.normalize) {
            if buffers[symbol] != nil || cumulative[symbol] != nil {
                buffers[symbol] = nil
                cumulative[symbol] = nil
                changed = true
            }
        }
        if changed {
            revision += 1
        }
    }

    func bars(for raw: String) -> [Bar] {
        buffers[SymbolCode.normalize(raw)] ?? []
    }

    func apply(_ incoming: StreamSecondBar) {
        let symbol = SymbolCode.normalize(incoming.symbol)
        guard !symbol.isEmpty, incoming.close.isFinite else { return }
        let previous = cumulative[symbol]
        let isSame = previous?.key == incoming.timeKey
        let deltaVolume: Double
        if isSame, let previous {
            deltaVolume = max(0, incoming.volume - previous.volume)
        } else {
            deltaVolume = max(0, incoming.volume)
        }
        cumulative[symbol] = (incoming.timeKey, incoming.volume)

        var bars = buffers[symbol] ?? []
        let epoch = Int(incoming.time.timeIntervalSince1970)
        if let last = bars.last, Int(last.time.timeIntervalSince1970) == epoch {
            var updated = last
            updated.open = incoming.open
            updated.high = incoming.high
            updated.low = incoming.low
            updated.close = incoming.close
            updated.volume += deltaVolume
            bars[bars.count - 1] = updated
        } else {
            bars.append(Bar(
                time: Date(timeIntervalSince1970: TimeInterval(epoch)),
                open: incoming.open,
                high: incoming.high,
                low: incoming.low,
                close: incoming.close,
                volume: deltaVolume
            ))
            if bars.count > Self.capacity {
                bars.removeFirst(bars.count - Self.capacity)
            }
        }
        buffers[symbol] = bars
        revision += 1
    }
}
