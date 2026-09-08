import Foundation
import UIKit
import UserNotifications

protocol NotificationAuthorizing: AnyObject {
    var isRemoteRegistrationAvailable: Bool { get }
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func registerForRemoteNotifications()
}

final class SystemNotificationAuthorization: NotificationAuthorizing {
    var canRegisterRemote: () -> Bool
    var isRemoteRegistrationAvailable: Bool { canRegisterRemote() }

    init(canRegisterRemote: @escaping () -> Bool = { FirebasePushRuntime.isConfigured }) {
        self.canRegisterRemote = canRegisterRemote
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            guard self.canRegisterRemote() else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}

@MainActor
final class FakeNotificationAuthorization: NotificationAuthorizing {
    var status: UNAuthorizationStatus
    var requestGranted: Bool
    var isRemoteRegistrationAvailable = true
    var pauseRequests = false
    private(set) var requestCount = 0
    private(set) var registerCount = 0
    private var requestContinuations: [CheckedContinuation<Bool, Never>] = []

    init(status: UNAuthorizationStatus = .authorized, requestGranted: Bool = true) {
        self.status = status
        self.requestGranted = requestGranted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        if pauseRequests {
            return await withCheckedContinuation { requestContinuations.append($0) }
        }
        status = requestGranted ? .authorized : .denied
        return requestGranted
    }

    func releaseRequests() {
        pauseRequests = false
        let pending = requestContinuations
        requestContinuations.removeAll()
        for continuation in pending {
            status = requestGranted ? .authorized : .denied
            continuation.resume(returning: requestGranted)
        }
    }

    func registerForRemoteNotifications() {
        registerCount += 1
    }
}

@MainActor
final class PushPreferenceStore: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var permissionDenied = false
    @Published private(set) var isUpdating = false

    var onEnabledChange: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private let authorization: NotificationAuthorizing
    private let key = "push_notifications_enabled"

    init(
        defaults: UserDefaults = .standard,
        authorization: NotificationAuthorizing = SystemNotificationAuthorization()
    ) {
        self.defaults = defaults
        self.authorization = authorization
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
            guard authorization.isRemoteRegistrationAvailable else {
                isEnabled = true
                persist()
                onEnabledChange?(true)
                return
            }
            let granted = await authorization.requestAuthorization()
            if !granted {
                isEnabled = false
                permissionDenied = true
                persist()
                onEnabledChange?(false)
                return
            }
            permissionDenied = false
        }

        isEnabled = enabled
        persist()
        onEnabledChange?(enabled)
    }

    func armRemoteNotifications() {
        authorization.registerForRemoteNotifications()
    }

    /// Login / foreground path: request once if the switch is on and status is undetermined.
    /// Does not re-prompt after a system denial. Never registers a token without display permission.
    func prepareForPush() async -> Bool {
        guard isEnabled else { return false }
        guard authorization.isRemoteRegistrationAvailable else { return false }
        let status = await authorization.authorizationStatus()
        switch status {
        case .notDetermined:
            let granted = await authorization.requestAuthorization()
            if granted {
                permissionDenied = false
                persist()
                return true
            }
            isEnabled = false
            permissionDenied = true
            persist()
            onEnabledChange?(false)
            return false
        case .authorized, .provisional, .ephemeral:
            permissionDenied = false
            return true
        default:
            permissionDenied = true
            return false
        }
    }

    private func persist() {
        defaults.set(isEnabled, forKey: key)
    }
}
