import Foundation

struct AutoExitBlacklist: Codable, Equatable {
    var takeProfit: [String]
    var stopLoss: [String]

    static let empty = AutoExitBlacklist(takeProfit: [], stopLoss: [])
}

@MainActor
final class AutoExitBlacklistStore: ObservableObject {
    @Published private(set) var values: AutoExitBlacklist

    private let disk: DiskStore
    private let file = "auto-exit-blacklist.json"

    init(disk: DiskStore = DiskStore()) {
        self.disk = disk
        values = disk.read(AutoExitBlacklist.self, name: file) ?? .empty
        normalizeInPlace()
    }

    func removeTakeProfit(_ symbol: String) {
        values.takeProfit = values.takeProfit.filter { $0 != Self.normalize(symbol) }
        persist()
    }

    func removeStopLoss(_ symbol: String) {
        values.stopLoss = values.stopLoss.filter { $0 != Self.normalize(symbol) }
        persist()
    }

    func addTakeProfit(_ symbol: String) {
        let symbol = Self.normalize(symbol)
        guard !symbol.isEmpty, !values.takeProfit.contains(symbol) else { return }
        values.takeProfit.append(symbol)
        values.takeProfit.sort()
        persist()
    }

    func addStopLoss(_ symbol: String) {
        let symbol = Self.normalize(symbol)
        guard !symbol.isEmpty, !values.stopLoss.contains(symbol) else { return }
        values.stopLoss.append(symbol)
        values.stopLoss.sort()
        persist()
    }

    func isTakeProfitBlocked(_ symbol: String) -> Bool {
        values.takeProfit.contains(Self.normalize(symbol))
    }

    func isStopLossBlocked(_ symbol: String) -> Bool {
        values.stopLoss.contains(Self.normalize(symbol))
    }

    private func persist() {
        disk.write(values, name: file)
    }

    private func normalizeInPlace() {
        values.takeProfit = Self.normalizeList(values.takeProfit)
        values.stopLoss = Self.normalizeList(values.stopLoss)
    }

    private static func normalize(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizeList(_ symbols: [String]) -> [String] {
        Array(Set(symbols.map(normalize).filter { !$0.isEmpty })).sorted()
    }
}
