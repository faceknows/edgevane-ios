import SwiftUI

@main
struct MoneyknowsApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .task {
                    await appModel.start()
                }
        }
    }
}
