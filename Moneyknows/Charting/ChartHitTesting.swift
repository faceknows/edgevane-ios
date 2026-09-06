import Foundation

enum ChartHitTesting {
    static let libraryIDBase = 1_000_000

    static func sorted(_ markers: [ChartMarker]) -> [ChartMarker] {
        markers.sorted {
            if $0.time != $1.time { return $0.time < $1.time }
            if $0.price != $1.price { return $0.price < $1.price }
            return $0.id < $1.id
        }
    }

    static func libraryID(index: Int) -> String {
        String(libraryIDBase + index)
    }

    static func pickedMarker(in markers: [ChartMarker], hoveredId: String?) -> ChartMarker? {
        guard let hoveredId, let raw = Int(hoveredId) else { return nil }
        let index = raw - libraryIDBase
        guard markers.indices.contains(index) else { return nil }
        return markers[index]
    }

    static func pickedBar(in bars: [Bar], at time: Date) -> Bar? {
        guard !bars.isEmpty else { return nil }
        if let match = bars.last(where: { $0.time <= time }) {
            return match
        }
        return bars.first
    }
}
