import SwiftUI

struct NewsToastBanner: View {
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        if let item = news.toast {
            ToastCard(
                id: item.id,
                onDismiss: {
                    if news.toast?.id == item.id {
                        news.clearToast()
                    }
                },
                onTap: {
                    news.clearToast()
                    router.openNews(item.id)
                }
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displaySymbol)
                        .font(.caption.weight(.semibold))
                    Text(item.displayHeadline)
                        .font(.footnote)
                        .lineLimit(2)
                }
                .foregroundColor(.primary)
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
}
