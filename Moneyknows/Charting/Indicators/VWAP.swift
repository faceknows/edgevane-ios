import Foundation

enum VWAP {
    static func series(from bars: [Bar]) -> [OverlayPoint] {
        var volume = 0.0
        var pv = 0.0
        return bars.map { bar in
            let typical = (bar.high + bar.low + bar.close) / 3
            volume += bar.volume
            pv += typical * bar.volume
            let value = volume == 0 ? bar.close : pv / volume
            return OverlayPoint(time: bar.time, value: value)
        }
    }
}
