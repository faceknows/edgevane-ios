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

    /// 按棒开始时刻合并；同一分钟以后到的为准，这样增量响应能更新正在形成的最后一根。
    static func mergeIncremental(_ existing: [Bar], with incoming: [Bar]) -> [Bar] {
        guard !incoming.isEmpty else { return existing }
        var byTime: [Date: Bar] = [:]
        for bar in existing {
            byTime[bar.time] = bar
        }
        for bar in incoming {
            byTime[bar.time] = bar
        }
        return byTime.values.sorted { $0.time < $1.time }
    }
}

enum DailyBars {
    static let pageCalendarDays = 100

    static func fromDTOs(_ dtos: [BarDTO]) -> [Bar] {
        var byDay: [String: Bar] = [:]
        for dto in dtos {
            guard let raw = dto.d, let time = BarTime.parse(raw),
                  let open = dto.o, let high = dto.h, let low = dto.l, let close = dto.c, let volume = dto.v
            else {
                continue
            }
            byDay[MarketClock.usDateString(from: time)] = Bar(
                time: time,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            )
        }
        return byDay.values.sorted { $0.time < $1.time }
    }

    static func merge(_ existing: [Bar], with incoming: [Bar]) -> [Bar] {
        var byDay: [String: Bar] = [:]
        for bar in existing + incoming {
            byDay[MarketClock.usDateString(from: bar.time)] = bar
        }
        return byDay.values.sorted { $0.time < $1.time }
    }

    static func needsLatest(_ bars: [Bar], now: Date = Date()) -> Bool {
        guard let last = bars.last else { return true }
        return MarketClock.usDateString(from: last.time) != MarketClock.lastTradingDate(from: now)
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

    static func bucketStart(_ time: Date, size: TimeInterval) -> Date {
        let seconds = time.timeIntervalSince1970
        let start = (seconds / size).rounded(.down) * size
        return Date(timeIntervalSince1970: start)
    }
}
