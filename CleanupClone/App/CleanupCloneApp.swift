import SwiftUI
import PostHog
import Adapty
import AdaptyUI
import UserNotifications

@main
struct CleanupCloneApp: App {
    @StateObject private var appFlow = AppFlow()
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate

    init() {
        // PostHog analytics
        let phConfig = PostHogConfig(
            apiKey: "phc_ppZgvrz3oNe987vEaU22d56uyxevAvuQhwTm8bcaF4pF",
            host: "https://us.i.posthog.com"
        )
        phConfig.captureScreenViews = false
        phConfig.sessionReplay = true
        phConfig.sessionReplayConfig.maskAllTextInputs = true
        phConfig.sessionReplayConfig.maskAllImages = false
        phConfig.sessionReplayConfig.screenshotMode = true
        phConfig.flushAt = 1                 // flush events immediately while debugging
        phConfig.flushIntervalSeconds = 10   // upload at least every 10s
        PostHogSDK.shared.setup(phConfig)

        // Adapty paywall + subscription management
        Task {
            try? await Adapty.activate("public_live_ctDqupOj.tMMK64DzTso1vaaCKpW2")
            try? await AdaptyUI.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appFlow)
                .onOpenURL { url in
                    if url.scheme == "cleanup" {
                        handleWidgetDeepLink(url)
                    } else {
                        appFlow.handleGoogleOpenURL(url)
                    }
                }
                .onAppear {
                    notificationDelegate.appFlow = appFlow
                    // Seed the App Group snapshot so widgets have data to render
                    // on first launch. `refresh(force:)` handles battery, storage
                    // and thermal; scan numbers come later via AppFlow.scanLibrary.
                    SharedSnapshotWriter.shared.refresh(force: true)
                    // If the user just tapped a widget (Water Eject / Dust Clean /
                    // Quick Clean), the widget extension wrote a pending action
                    // into the App Group and asked iOS to foreground us.
                    handlePendingWidgetAction()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )) { _ in
                    SharedSnapshotWriter.shared.refresh()
                    handlePendingWidgetAction()
                }
        }
    }

    @MainActor
    private func handlePendingWidgetAction() {
        guard let action = WidgetIntentBridge.consumePending() else { return }
        switch action {
        case .waterEject(let seconds):
            SharedToneEngine.shared.start(mode: .water, seconds: seconds)
            WidgetAutoSuspend.suspendToHome()
        case .dustClean(let seconds):
            SharedToneEngine.shared.start(mode: .dust, seconds: seconds)
            WidgetAutoSuspend.suspendToHome()
        case .quickClean:
            // Opens the app to the Dashboard — no auto-suspend here, because
            // Quick Clean is meant to land the user IN the app so they can
            // see what was freed.
            appFlow.selectTab(.home)
        }
    }

    /// Handles `cleanup://` deep links fired by widget taps.
    ///
    /// Paths:
    /// - `cleanup://run/water` → start 165 Hz water-ejection tone (30s)
    /// - `cleanup://run/dust`  → start 1–6 kHz dust-cleaning sweep (30s)
    /// - `cleanup://run/quick` → open the Dashboard so the user can run a scan
    ///
    /// Water / Dust auto-suspend to the Home Screen once the tone starts so
    /// the user hears the effect without the app covering the screen. The
    /// app target has `UIBackgroundModes = audio` so playback continues.
    @MainActor
    private func handleWidgetDeepLink(_ url: URL) {
        guard url.host == "run", let action = url.pathComponents.dropFirst().first else { return }
        let defaultSeconds = 30
        switch action {
        case "water":
            SharedToneEngine.shared.start(mode: .water, seconds: defaultSeconds)
            WidgetAutoSuspend.suspendToHome()
        case "dust":
            SharedToneEngine.shared.start(mode: .dust, seconds: defaultSeconds)
            WidgetAutoSuspend.suspendToHome()
        case "quick":
            appFlow.selectTab(.home)
        default:
            break
        }
    }
}

/// Handles taps on our aggressive local-notification campaign. Each
/// notification carries a `deeplink` userInfo key — we route to the matching
/// AppFlow screen / upgrade sheet so the tap lands on the conversion surface
/// the copy promised.
final class NotificationDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    weak var appFlow: AppFlow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show banners even when app is foregrounded — otherwise a user who
    // opens the app during a scheduled fire would miss the nudge.
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let deeplink = NotificationScheduler.deeplink(from: userInfo)
        route(deeplink)
        completionHandler()
    }

    @MainActor
    private func route(_ deeplink: NotificationDeeplink?) {
        guard let appFlow, let deeplink else { return }
        switch deeplink {
        case .upgrade:
            appFlow.requestUpgrade(for: .photoDelete)
        case .duplicates:
            appFlow.selectTab(.home)
        case .compress:
            appFlow.selectTab(.compress)
        case .vault:
            appFlow.selectTab(.secret)
        case .dashboard:
            appFlow.selectTab(.home)
        }
    }
}
