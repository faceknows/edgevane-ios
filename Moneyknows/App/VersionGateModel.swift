import Foundation

enum VersionGateState: Equatable {
    case checking
    case failed(String)
    case blocked(message: String, storeURL: URL)
    case passed
}

@MainActor
final class VersionGateModel: ObservableObject {
    @Published private(set) var state: VersionGateState = .checking

    private let api: VersionAPI

    init(api: VersionAPI) {
        self.api = api
    }

    private var checkGeneration: UInt64 = 0

    func check() async {
        checkGeneration += 1
        let generation = checkGeneration
        state = .checking
        do {
            let info = try await api.check()
            guard generation == checkGeneration else { return }
            if info.forceUpgrade == true {
                block(message: info.upgradeMessage, store: info.storeUrl)
                return
            }
            state = .passed
            AppLog.app.info("version check passed \(AppEnvironment.appVersion, privacy: .public)")
        } catch let AppError.versionUnsupported(message, storeURL) {
            guard generation == checkGeneration else { return }
            block(message: message, store: storeURL?.absoluteString)
        } catch {
            guard generation == checkGeneration else { return }
            let text = UserFacingError.message(from: error) ?? L10n.Version.failed
            state = .failed(text)
            AppLog.app.error("version check failed")
        }
    }

    private func block(message: String?, store: String?) {
        let url = store.flatMap(URL.init(string:)) ?? AppEnvironment.defaultStoreURL
        state = .blocked(message: message ?? L10n.Version.updateRequired, storeURL: url)
        AppLog.app.info("version blocked")
    }
}
