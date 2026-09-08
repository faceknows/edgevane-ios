import SwiftUI

struct NewsListView: View {
    @EnvironmentObject private var news: NewsStore

    var body: some View {
        Group {
            if news.items.isEmpty {
                EmptyStateView(title: L10n.News.emptyTitle, message: L10n.News.emptyBody)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(news.items) { item in
                    NavigationLink(destination: NewsDetailView(newsID: item.id)) {
                        NewsRow(item: item)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L10n.News.title)
    }
}

struct NewsRow: View {
    var item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.displaySymbol)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
                Spacer()
                Text(NewsTime.listLabel(for: item))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text(item.displayHeadline)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

struct NewsDetailView: View {
    var newsID: String
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if let item = news.item(id: newsID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(item.displaySymbol)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.accentColor)
                            Spacer()
                            if let symbol = item.symbol, SymbolCode.isValid(symbol) {
                                Button(L10n.News.openSymbol) {
                                    router.openSymbol(symbol)
                                }
                            }
                        }
                        Text(item.displayHeadline)
                            .font(.title3.weight(.semibold))
                        Text(L10n.News.source(item.source ?? "—"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(L10n.News.published(NewsTime.absolute(item.publishedAt)))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(L10n.News.received(NewsTime.absolute(item.receivedAt)))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        if let summary = item.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.body)
                        }
                        if let urlText = item.url, let url = URL(string: urlText) {
                            Link(L10n.News.openLink, destination: url)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyStateView(title: L10n.News.notFoundTitle, message: L10n.News.notFoundBody)
                    .padding()
            }
        }
        .navigationTitle(L10n.News.detailTitle)
    }
}

enum NewsTime {
    static func listLabel(for item: NewsItem, now: Date = Date()) -> String {
        "\(relative(item.receivedAt, now: now)) • \(absolute(item.receivedAt))"
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let diff = max(0, now.timeIntervalSince(date))
        if diff < 60 { return L10n.News.justNow }
        if diff < 3_600 { return L10n.News.minutesAgo(Int(diff / 60)) }
        if diff < 86_400 { return L10n.News.hoursAgo(Int(diff / 3_600)) }
        if diff < 86_400 * 7 { return L10n.News.daysAgo(Int(diff / 86_400)) }
        return absolute(date, includeTime: false)
    }

    static func absolute(_ date: Date?, includeTime: Bool = true) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = includeTime ? .short : .none
        return formatter.string(from: date)
    }
}
