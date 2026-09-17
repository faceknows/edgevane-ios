import SwiftUI

struct AppToastOverlay: View {
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var notifications: NotificationStore

    var body: some View {
        VStack(spacing: 8) {
            TradingNoticeBanner()
            NewsToastBanner()
            NotificationToastBanner()
        }
        .animation(.easeInOut(duration: 0.22), value: trading.notice?.id)
        .animation(.easeInOut(duration: 0.22), value: news.toast?.id)
        .animation(.easeInOut(duration: 0.22), value: notifications.toast?.id)
    }
}

extension View {
    func appToastOverlay() -> some View {
        overlay(alignment: .top) {
            AppToastOverlay()
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
    }
}
