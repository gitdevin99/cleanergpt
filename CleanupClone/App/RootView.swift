import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appFlow: AppFlow
    @StateObject private var entitlements = EntitlementStore.shared
    @StateObject private var upgradePaywallStore = PaywallStore()
    @State private var showUpgradePaywall = false

    private var upgradePaywallBinding: Binding<Bool> {
        Binding(
            get: { showUpgradePaywall || appFlow.presentUpgradePaywall },
            set: { newValue in
                showUpgradePaywall = newValue
                appFlow.presentUpgradePaywall = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            CleanupTheme.background.ignoresSafeArea()

            switch appFlow.stage {
            case .splash:
                SplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingFlowView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .paywall:
                PaywallView()
                    .transition(.opacity)
            case .mainApp:
                MainShellView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(appFlow.appearancePreference.colorScheme)
        .animation(.easeInOut(duration: 0.35), value: appFlow.stage)
        .environmentObject(entitlements)
        .environmentObject(upgradePaywallStore)
        .sheet(item: $appFlow.pendingUpgradeGate) { ctx in
            UpgradeGateSheet(
                context: ctx,
                onUpgrade: {
                    appFlow.pendingUpgradeGate = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showUpgradePaywall = true
                    }
                },
                onDismiss: { appFlow.pendingUpgradeGate = nil }
            )
            .environmentObject(entitlements)
        }
        .fullScreenCover(isPresented: upgradePaywallBinding) {
            UpgradePaywallSheet(
                onDismiss: {
                    showUpgradePaywall = false
                    appFlow.presentUpgradePaywall = false
                },
                onPurchased: {
                    showUpgradePaywall = false
                    appFlow.presentUpgradePaywall = false
                    Task { await entitlements.refreshFromAdapty() }
                }
            )
            .environmentObject(upgradePaywallStore)
            .environmentObject(entitlements)
        }
    }
}
