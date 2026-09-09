import Foundation

struct MinuteIndicatorSnapshot: Equatable {
    var rsi: Double?
    var adx: Double?
    var plusDI: Double?
    var minusDI: Double?
    var atr: Double?
    var atrPct: Double?
}

enum MinuteIndicators {
    static let period = 10

    static func snapshot(
        bars1m: [Bar],
        interval: MinuteInterval,
        period: Int = period
    ) -> MinuteIndicatorSnapshot {
        let bars = BarAggregator.aggregate(bars1m, minutes: interval.minutes)
        let adx = adxSeries(bars, period: period)
        let atr = averageATR(bars, count: period)
        let close = bars.last?.close
        let atrPct: Double?
        if let atr, let close, close.isFinite, close != 0 {
            atrPct = (atr / close) * 100
        } else {
            atrPct = nil
        }
        return MinuteIndicatorSnapshot(
            rsi: latest(rsiSeries(bars, period: period)),
            adx: latest(adx.adx),
            plusDI: latest(adx.plusDI),
            minusDI: latest(adx.minusDI),
            atr: atr,
            atrPct: atrPct
        )
    }

    static func latest(_ values: [Double?]) -> Double? {
        for value in values.reversed() {
            if let value, value.isFinite { return value }
        }
        return nil
    }

    static func rsiSeries(_ bars: [Bar], period: Int) -> [Double?] {
        var values = Array<Double?>(repeating: nil, count: bars.count)
        guard bars.count > period, period > 0 else { return values }

        var gainSum = 0.0
        var lossSum = 0.0
        for index in 1...period {
            let change = bars[index].close - bars[index - 1].close
            if change > 0 {
                gainSum += change
            } else {
                lossSum -= change
            }
        }

        var averageGain = gainSum / Double(period)
        var averageLoss = lossSum / Double(period)
        values[period] = finite(rsi(gain: averageGain, loss: averageLoss))

        if period + 1 < bars.count {
            for index in (period + 1)..<bars.count {
                let change = bars[index].close - bars[index - 1].close
                let gain = change > 0 ? change : 0
                let loss = change < 0 ? -change : 0
                averageGain = (averageGain * Double(period - 1) + gain) / Double(period)
                averageLoss = (averageLoss * Double(period - 1) + loss) / Double(period)
                values[index] = finite(rsi(gain: averageGain, loss: averageLoss))
            }
        }
        return values
    }

    static func averageATR(_ bars: [Bar], count: Int) -> Double? {
        guard bars.count >= 2, count > 0 else { return nil }
        let available = min(count, bars.count - 1)
        let start = bars.count - available
        var sum = 0.0
        for index in start..<bars.count {
            sum += trueRange(current: bars[index], previous: bars[index - 1])
        }
        return finite(sum / Double(available))
    }

    static func adxSeries(_ bars: [Bar], period: Int) -> (adx: [Double?], plusDI: [Double?], minusDI: [Double?]) {
        let length = bars.count
        var adx = Array<Double?>(repeating: nil, count: length)
        var plusDI = Array<Double?>(repeating: nil, count: length)
        var minusDI = Array<Double?>(repeating: nil, count: length)
        guard length > period, period > 0 else {
            return (adx, plusDI, minusDI)
        }

        var trSum = 0.0
        var plusDMSum = 0.0
        var minusDMSum = 0.0
        var dxSum = 0.0
        var adxValue: Double?

        for index in 1..<length {
            let current = bars[index]
            let previous = bars[index - 1]
            let upMove = current.high - previous.high
            let downMove = previous.low - current.low
            let plusDM = upMove > downMove && upMove > 0 ? upMove : 0
            let minusDM = downMove > upMove && downMove > 0 ? downMove : 0
            let trueRange = trueRange(current: current, previous: previous)

            if index <= period {
                trSum += trueRange
                plusDMSum += plusDM
                minusDMSum += minusDM
            } else {
                trSum = trSum - trSum / Double(period) + trueRange
                plusDMSum = plusDMSum - plusDMSum / Double(period) + plusDM
                minusDMSum = minusDMSum - minusDMSum / Double(period) + minusDM
            }
            guard index >= period else { continue }

            let nextPlusDI = trSum == 0 ? 0 : plusDMSum / trSum * 100
            let nextMinusDI = trSum == 0 ? 0 : minusDMSum / trSum * 100
            let diSum = nextPlusDI + nextMinusDI
            let dx = diSum == 0 ? 0 : abs(nextPlusDI - nextMinusDI) / diSum * 100
            plusDI[index] = finite(nextPlusDI)
            minusDI[index] = finite(nextMinusDI)

            if index < period * 2 - 1 {
                dxSum += dx
                continue
            }
            if adxValue == nil {
                dxSum += dx
                adxValue = dxSum / Double(period)
            } else if let currentADX = adxValue {
                adxValue = (currentADX * Double(period - 1) + dx) / Double(period)
            }
            adx[index] = adxValue.flatMap(finite)
        }
        return (adx, plusDI, minusDI)
    }

    private static func trueRange(current: Bar, previous: Bar) -> Double {
        max(
            current.high - current.low,
            abs(current.high - previous.close),
            abs(current.low - previous.close)
        )
    }

    private static func rsi(gain: Double, loss: Double) -> Double {
        if loss == 0 {
            return gain == 0 ? 0 : 100
        }
        return 100 - 100 / (1 + gain / loss)
    }

    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }
}
