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
            ToastCard(
                id: item.id,
                onDismiss: {
                    if notifications.toast?.id == item.id {
                        notifications.clearToast()
                    }
                },
                onTap: {
                    notifications.clearToast()
                    router.handleNotification(
                        item,
                        versionPassed: appModel.versionGate.state == .passed,
                        signedIn: appModel.session.isSignedIn,
                        currentUserId: appModel.session.user?.id,
                        alreadyShowingHistory: router.isShowingNotificationHistory
                    )
                }
            ) {
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
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    private func toastTitle(_ item: AppNotification) -> String {
        NotificationParser.displayTitle(for: item)
    }
}
