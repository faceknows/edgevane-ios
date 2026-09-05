import Foundation

enum AppEnvironmentName: String {
    case development
    case staging
    case production
}

enum AppEnvironment {
    static var name: AppEnvironmentName {
        let raw = string("MKEnvName") ?? "development"
        return AppEnvironmentName(rawValue: raw) ?? .development
    }

    static var apiURL: URL {
        url("MKAPIURL") ?? URL(string: "https://money-api.byteknows.com")!
    }

    static var socketHost: URL {
        url("MKSocketHost") ?? URL(string: "https://money-gateway.byteknows.com")!
    }

    static var apiTimeout: TimeInterval {
        let raw = string("MKAPITimeout") ?? "30"
        return TimeInterval(raw) ?? 30
    }

    static var enableLogging: Bool {
        (string("MKEnableLogging") ?? "NO").uppercased() == "YES"
    }

    static var isProduction: Bool {
        name == .production
    }

    static var appVersion: String {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return normalizeVersion(raw)
    }

    static let platformHeader = "ios"

    static var defaultStoreURL: URL {
        URL(string: "https://apps.apple.com")!
    }

    /// Shown on auth / settings so a Debug build pointed at a LAN host is obvious.
    static var debugSummary: String {
        "\(name.rawValue) · \(apiURL.absoluteString)"
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func url(_ key: String) -> URL? {
        string(key).flatMap(URL.init(string:))
    }

    private static func normalizeVersion(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "0.0.0"
        }
        if let match = trimmed.range(of: #"\d+(?:\.\d+){0,2}"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return trimmed
    }
}
