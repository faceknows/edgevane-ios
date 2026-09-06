import SwiftUI

enum AppearancePreference: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    @Published var preference: AppearancePreference {
        didSet { persist() }
    }

    private let disk: DiskStore
    private let file = "appearance.json"

    init(disk: DiskStore = DiskStore()) {
        self.disk = disk
        preference = disk.read(AppearanceRecord.self, name: file)?.preference ?? .system
    }

    private func persist() {
        disk.write(AppearanceRecord(preference: preference), name: file)
    }
}

private struct AppearanceRecord: Codable {
    var preference: AppearancePreference
}
