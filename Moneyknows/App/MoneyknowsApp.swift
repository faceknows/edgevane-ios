import SwiftUI

@main
struct MoneyknowsApp: App {
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootContainer(
                appearance: appModel.appearance,
                preferences: appModel.preferences
            )
            .environmentObject(appModel)
            .environmentObject(appModel.session)
            .environmentObject(appModel.preferences)
            .environmentObject(appModel.appearance)
            .environmentObject(appModel.blacklist)
            .environmentObject(appModel.brokerage)
            .environmentObject(appModel.profile)
            .environmentObject(appModel.pushPreference)
            .environmentObject(appModel.screeners)
            .environmentObject(appModel.summaries)
            .environmentObject(appModel.bars)
            .environmentObject(appModel.realtime)
            .environmentObject(appModel.realtime.subscriptions)
            .environmentObject(appModel.realtime.quotes)
            .environmentObject(appModel.realtime.seconds)
            .environmentObject(appModel.router)
            .task {
                await appModel.start()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    appModel.ensureRealtimeConnected()
                }
            }
        }
    }
}

private struct RootContainer: View {
    @ObservedObject var appearance: AppearanceStore
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        RootView()
            .preferredColorScheme(appearance.preference.colorScheme)
            .id(preferences.localeRevision)
    }
}
