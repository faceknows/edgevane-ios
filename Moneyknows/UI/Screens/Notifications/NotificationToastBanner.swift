import SwiftUI

struct NotificationToastBanner: View {
    @EnvironmentObject private var notifications: NotificationStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        if let item = notifications.toast,
           NotificationVolume.passes(item, threshold: preferences.values.notificationVolumeThreshold)
        {
            Button {
                notifications.clearToast()
                router.handleNotification(
                    item,
                    versionPassed: appModel.versionGate.state == .passed,
                    signedIn: appModel.session.isSignedIn,
                    currentUserId: appModel.session.user?.id,
                    alreadyShowingHistory: router.isShowingNotificationHistory
                )
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(toastTitle(item))
                        .font(.caption.weight(.semibold))
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.footnote)
                            .lineLimit(2)
                    }
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .buttonStyle(.plain)
        }
    }

    private func toastTitle(_ item: AppNotification) -> String {
        NotificationParser.displayTitle(for: item)
    }
}
