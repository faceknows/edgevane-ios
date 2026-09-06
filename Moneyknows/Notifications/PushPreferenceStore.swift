import Foundation
import UserNotifications

@MainActor
final class PushPreferenceStore: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var permissionDenied = false
    @Published private(set) var isUpdating = false

    private let defaults: UserDefaults
    private let key = "push_notifications_enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: key) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: key)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        if enabled {
            let granted = await requestPermission()
            if !granted {
                isEnabled = false
                permissionDenied = true
                persist()
                return
            }
            permissionDenied = false
        }

        isEnabled = enabled
        persist()
    }

    private func persist() {
        defaults.set(isEnabled, forKey: key)
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}
