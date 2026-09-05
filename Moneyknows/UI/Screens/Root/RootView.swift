import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        RootSwitcher(versionGate: appModel.versionGate, session: appModel.session)
    }
}

private struct RootSwitcher: View {
    @ObservedObject var versionGate: VersionGateModel
    @ObservedObject var session: SessionStore

    var body: some View {
        Group {
            switch versionGate.state {
            case .passed:
                if session.isRestoringSession {
                    ProgressView()
                } else if session.isSignedIn {
                    MainTabView()
                } else {
                    NavigationView {
                        LoginView()
                    }
                    .navigationViewStyle(.stack)
                }
            default:
                VersionGateView(model: versionGate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}
