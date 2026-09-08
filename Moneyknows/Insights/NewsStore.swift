import Foundation

enum NewsSource: Equatable {
    case alpaca
    case ibkr
}

struct NewsItem: Equatable, Identifiable, Codable {
    var id: String
    var symbol: String?
    var headline: String?
    var summary: String?
    var source: String?
    var url: String?
    var publishedAt: Date?
    var receivedAt: Date

    var displayHeadline: String {
        headline ?? L10n.News.untitled
    }

    var displaySymbol: String {
        symbol ?? L10n.News.fallbackSymbol
    }
}

enum HTMLText {
    private static let named: [String: String] = [
        "amp": "&",
        "apos": "'",
        "gt": ">",
        "hellip": "...",
        "ldquo": "\"",
        "lsquo": "'",
        "lt": "<",
        "mdash": "-",
        "nbsp": " ",
        "ndash": "-",
        "quot": "\"",
        "rdquo": "\"",
        "rsquo": "'",
    ]

    static func decode(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var text = raw
        text = text.replacingOccurrences(
            of: #"<\s*br\s*/?\s*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</\s*(p|div|li|h[1-6]|tr)\s*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func decodeEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "&(#x?[0-9a-f]+|[a-z][a-z0-9]+);",
            options: .caseInsensitive
        ) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var output = ""
        var cursor = text.startIndex
        for match in matches {
            guard let full = Range(match.range, in: text),
                  match.numberOfRanges >= 2,
                  let inner = Range(match.range(at: 1), in: text)
            else { continue }
            output += text[cursor..<full.lowerBound]
            output += decodeEntity(String(text[inner]))
            cursor = full.upperBound
        }
        output += text[cursor...]
        return output
    }

    private static func decodeEntity(_ entity: String) -> String {
        let normalized = entity.lowercased()
        if let named = named[normalized] { return named }
        if normalized.hasPrefix("#x") {
            let digits = String(normalized.dropFirst(2))
            if let value = UInt32(digits, radix: 16), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
        } else if normalized.hasPrefix("#") {
            let digits = String(normalized.dropFirst())
            if let value = UInt32(digits), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
        }
        return "&\(entity);"
    }
}

@MainActor
final class NewsStore: ObservableObject {
    static let capacity = 500
    static let cacheName = "news-store.json"

    @Published private(set) var items: [NewsItem] = []
    @Published private(set) var toast: NewsItem?
    var isForeground = true
    private(set) var isActive = true

    private let disk: DiskStoring
    private var toastTask: Task<Void, Never>?

    init(disk: DiskStoring = DiskStore()) {
        self.disk = disk
        items = Self.normalized(disk.read([NewsItem].self, name: Self.cacheName) ?? [])
    }

    func activate() {
        isActive = true
    }

    func item(id: String) -> NewsItem? {
        items.first { $0.id == id }
    }

    @discardableResult
    func ingest(_ item: NewsItem) -> Bool {
        guard isActive, !item.id.isEmpty else { return false }
        let isNew = !items.contains { $0.id == item.id }
        items = Self.normalized([item] + items)
        persist()
        if isNew, isForeground {
            presentToast(item)
        }
        return isNew
    }

    @discardableResult
    func ingest(_ data: Data, source: NewsSource, now: Date = Date()) -> Bool {
        guard let item = MarketStreamPayload.news(from: data, source: source, now: now) else {
            return false
        }
        return ingest(item)
    }

    func clearToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    func reset() {
        isActive = false
        items = []
        clearToast()
        disk.delete(name: Self.cacheName)
    }

    private func persist() {
        disk.write(items, name: Self.cacheName)
    }

    private func presentToast(_ item: NewsItem) {
        toastTask?.cancel()
        toast = item
        let id = item.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == id {
                self?.toast = nil
            }
        }
    }

    static func normalized(_ items: [NewsItem]) -> [NewsItem] {
        var unique: [String: NewsItem] = [:]
        unique.reserveCapacity(items.count)
        for item in items where !item.id.isEmpty {
            if unique[item.id] == nil {
                unique[item.id] = item
            }
        }
        return unique.values
            .sorted { $0.receivedAt > $1.receivedAt }
            .prefix(capacity)
            .map { $0 }
    }
}
