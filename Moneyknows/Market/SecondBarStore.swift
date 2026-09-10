import Foundation

@MainActor
final class SecondBarStore: ObservableObject {
    nonisolated static let capacity = 10 * 60

    @Published private(set) var revision: UInt64 = 0

    private var buffers: [String: [Bar]] = [:]
    private var cumulative: [String: (key: String, volume: Double)] = [:]

    func reset() {
        buffers = [:]
        cumulative = [:]
        revision += 1
        interruptExpiry()
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
            interruptExpiry()
        }
    }

    func bars(for raw: String) -> [Bar] {
        buffers[SymbolCode.normalize(raw)] ?? []
    }

    func apply(_ incoming: StreamSecondBar, now: Date = Date()) {
        let symbol = SymbolCode.normalize(incoming.symbol)
        guard !symbol.isEmpty, incoming.close.isFinite, incoming.time <= now else { return }
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
        interruptExpiry()
    }

    @discardableResult
    func dropExpired(now: Date = Date(), window: TimeInterval = TimeInterval(capacity)) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        var changed = false
        for (symbol, bars) in buffers {
            let trimmed = bars.filter { $0.time >= cutoff && $0.time <= now }
            if trimmed.count == bars.count { continue }
            if trimmed.isEmpty {
                buffers[symbol] = nil
            } else {
                buffers[symbol] = trimmed
            }
            changed = true
        }
        if changed {
            revision += 1
        }
        return changed
    }

    func nextWake(now: Date = Date(), window: TimeInterval = TimeInterval(capacity)) -> Date? {
        var soonest: Date?
        for bars in buffers.values {
            for bar in bars {
                let event = bar.time.addingTimeInterval(window + Self.expirySlack)
                guard event > now else { continue }
                soonest = soonest.map { min($0, event) } ?? event
            }
        }
        return soonest
    }

    func sleepNanoseconds(now: Date = Date()) -> UInt64 {
        let delay: TimeInterval
        if let wake = nextWake(now: now) {
            delay = min(max(Self.expirySlack, wake.timeIntervalSince(now)), Self.maxSleep)
        } else {
            delay = Self.maxSleep
        }
        return UInt64(delay * 1_000_000_000)
    }

    func startExpiring() async {
        expiryLoopID += 1
        let loopID = expiryLoopID
        interruptExpiry()
        while !Task.isCancelled, expiryLoopID == loopID {
            _ = dropExpired(now: Date())
            let finished = await sleepForExpiry(sleepNanoseconds(now: Date()))
            guard !Task.isCancelled, expiryLoopID == loopID else { return }
            if finished, nextWake(now: Date()) != nil, !dropExpired(now: Date()) {
                revision += 1
            }
        }
    }

    private func interruptExpiry() {
        expirySleepID += 1
        expirySleep?.cancel()
        expirySleep = nil
    }

    private func sleepForExpiry(_ nanoseconds: UInt64) async -> Bool {
        expirySleepID += 1
        let sleepID = expirySleepID
        expirySleep?.cancel()
        let sleep = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            return
        }
        expirySleep = sleep
        await withTaskCancellationHandler {
            await sleep.value
        } onCancel: {
            sleep.cancel()
        }
        let finished = !sleep.isCancelled
        if expirySleepID == sleepID {
            expirySleep = nil
        }
        return finished
    }

    private var expiryLoopID: UInt64 = 0
    private var expirySleepID: UInt64 = 0
    private var expirySleep: Task<Void, Never>?
    private nonisolated static let expirySlack: TimeInterval = 0.05
    nonisolated static let maxSleep: TimeInterval = 24 * 60 * 60
}
