import Foundation

enum MinuteBars {
    static func fromDTOs(_ dtos: [BarDTO], date: String) -> [Bar] {
        dtos.compactMap { dto in
            guard let raw = dto.d, let time = BarTime.parse(raw, date: date),
                  let open = dto.o, let high = dto.h, let low = dto.l, let close = dto.c, let volume = dto.v
            else {
                return nil
            }
            return Bar(time: time, open: open, high: high, low: low, close: close, volume: volume)
        }
        .sorted { $0.time < $1.time }
    }
}

enum BarAggregator {
    static func aggregate(_ bars: [Bar], minutes: Int) -> [Bar] {
        guard minutes > 1 else { return bars }
        return bucket(bars, size: TimeInterval(minutes * 60))
    }

    static func aggregate(_ bars: [Bar], seconds: Int) -> [Bar] {
        guard seconds > 1 else { return bars }
        return bucket(bars, size: TimeInterval(seconds))
    }

    private static func bucket(_ bars: [Bar], size: TimeInterval) -> [Bar] {
        guard size > 0, !bars.isEmpty else { return bars }
        var grouped: [(start: Date, bar: Bar)] = []
        for bar in bars {
            let start = bucketStart(bar.time, size: size)
            if let last = grouped.last, last.start == start {
                var merged = last.bar
                merged.high = max(merged.high, bar.high)
                merged.low = min(merged.low, bar.low)
                merged.close = bar.close
                merged.volume += bar.volume
                grouped[grouped.count - 1].bar = merged
            } else {
                grouped.append((start, Bar(
                    time: start,
                    open: bar.open,
                    high: bar.high,
                    low: bar.low,
                    close: bar.close,
                    volume: bar.volume
                )))
            }
        }
        return grouped.map(\.bar)
    }

    private static func bucketStart(_ time: Date, size: TimeInterval) -> Date {
        let seconds = time.timeIntervalSince1970
        let start = (seconds / size).rounded(.down) * size
        return Date(timeIntervalSince1970: start)
    }
}
