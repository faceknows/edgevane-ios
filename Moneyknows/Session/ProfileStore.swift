import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var roleConfiguration: RoleConfiguration?
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private let api: UserAPI
    private let session: SessionStore
    private var epoch: UInt64 = 0

    init(api: UserAPI, session: SessionStore) {
        self.api = api
        self.session = session
    }

    func reset() {
        epoch += 1
        roleConfiguration = nil
        errorText = nil
        isLoading = false
    }

    func refresh() async {
        let epoch = self.epoch
        let generation = session.generation
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        await refreshIdentity(epoch: epoch, generation: generation)
        await refreshRoleConfiguration(epoch: epoch, generation: generation)
    }

    func refreshIdentity() async {
        let epoch = self.epoch
        let generation = session.generation
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        await refreshIdentity(epoch: epoch, generation: generation)
    }

    func refreshRoleConfiguration() async {
        let epoch = self.epoch
        let generation = session.generation
        await refreshRoleConfiguration(epoch: epoch, generation: generation)
    }

    private func refreshIdentity(epoch: UInt64, generation: UInt64) async {
        do {
            let dto = try await api.me()
            guard isCurrent(epoch: epoch, generation: generation) else { return }
            session.applyUser(AppUser(dto: dto))
        } catch {
            guard isCurrent(epoch: epoch, generation: generation) else { return }
            if !error.isCancellation {
                errorText = UserFacingError.message(from: error)
                AppLog.session.error("profile refresh failed")
            }
        }
    }

    private func refreshRoleConfiguration(epoch: UInt64, generation: UInt64) async {
        do {
            let configuration = try await api.roleConfiguration()
            guard isCurrent(epoch: epoch, generation: generation) else { return }
            roleConfiguration = configuration
        } catch {
            guard isCurrent(epoch: epoch, generation: generation) else { return }
            if error.isCancellation { return }
            if errorText == nil {
                errorText = UserFacingError.message(from: error)
            }
            AppLog.session.error("role-config refresh failed")
        }
    }

    private func isCurrent(epoch: UInt64, generation: UInt64) -> Bool {
        self.epoch == epoch && session.generation == generation
    }
}
