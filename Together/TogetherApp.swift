import SwiftUI

@main
struct TogetherApp: App {
    @State private var appContext = AppContext.bootstrap()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appContext)
                .task {
                    await appContext.bootstrapIfNeeded()
                }
        }
    }
}
