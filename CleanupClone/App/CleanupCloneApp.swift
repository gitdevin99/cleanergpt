import SwiftUI

@main
struct CleanupCloneApp: App {
    @StateObject private var appFlow = AppFlow()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appFlow)
                .onOpenURL { url in
                    appFlow.handleGoogleOpenURL(url)
                }
        }
    }
}
