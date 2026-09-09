import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

enum FirebaseAppIdentity {
    static func matches(appBundleID: String?, plistBundleID: String?) -> Bool {
        guard let appBundleID, let plistBundleID,
              !appBundleID.isEmpty, !plistBundleID.isEmpty
        else { return false }
        return appBundleID == plistBundleID
    }

    static func plistBundleID(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url)
        else { return nil }
        return dict["BUNDLE_ID"] as? String
    }

    /// Production Firebase iOS app only. Debug/Staging bundle IDs do not match
    /// `GoogleService-Info.plist`; configuring anyway would bind Messaging to an
    /// APNs identity the production app cannot deliver to.
    static func shouldConfigure(
        appBundleID: String?,
        plistBundleID: String?,
        runningTests: Bool
    ) -> Bool {
        guard !runningTests else { return false }
        return matches(appBundleID: appBundleID, plistBundleID: plistBundleID)
    }
}

enum FirebasePushRuntime {
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    static func configureIfNeeded(
        appBundleID: String? = Bundle.main.bundleIdentifier,
        plistBundleID: String? = FirebaseAppIdentity.plistBundleID(),
        runningTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    ) -> Bool {
        guard FirebaseAppIdentity.shouldConfigure(
            appBundleID: appBundleID,
            plistBundleID: plistBundleID,
            runningTests: runningTests
        ) else {
            if !runningTests {
                AppLog.push.info("firebase plist bundle mismatch, skip FCM")
            }
            return false
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return FirebaseApp.app() != nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if FirebasePushRuntime.configureIfNeeded() {
            Messaging.messaging().delegate = self
        }
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            PushInbox.shared.receiveOpen(Self.notification(from: userInfo))
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebasePushRuntime.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            PushInbox.shared.setToken(fcmToken)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let item = Self.notification(from: notification)
        Task { @MainActor in
            PushInbox.shared.receiveForeground(item)
        }
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let item = Self.notification(from: response.notification)
        Task { @MainActor in
            PushInbox.shared.receiveOpen(item)
        }
        completionHandler()
    }

    private static func notification(from notification: UNNotification) -> AppNotification {
        let content = notification.request.content
        return NotificationHistory.mapRemote(
            userInfo: content.userInfo,
            title: content.title,
            body: content.body,
            messageID: notification.request.identifier
        )
    }

    private static func notification(from userInfo: [AnyHashable: Any]) -> AppNotification {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let alert = aps?["alert"] as? [AnyHashable: Any]
        let title = NotificationJSON.readString(alert?["title"]) ?? NotificationJSON.readString(userInfo["title"])
        let body = NotificationJSON.readString(alert?["body"])
            ?? NotificationJSON.readString(alert?["subtitle"])
            ?? NotificationJSON.readString(userInfo["body"])
        return NotificationHistory.mapRemote(
            userInfo: userInfo,
            title: title,
            body: body,
            messageID: NotificationJSON.readString(userInfo["gcm.message_id"])
        )
    }
}
